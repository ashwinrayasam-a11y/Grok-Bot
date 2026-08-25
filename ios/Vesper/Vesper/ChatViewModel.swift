import Combine
import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var emotion = EmotionState()
    @Published var mode: LinkMode = .checking
    @Published var isThinking = false
    @Published var isHearing = false
    @Published var hearingStatus: String?
    @Published var banner: String? {
        didSet {
            bannerTask?.cancel()
            guard banner != nil else { return }
            bannerTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.banner = nil
            }
        }
    }

    let voice = VoicePlayer()

    private var bannerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            SettingsKeys.macURL: SettingsKeys.defaultMacURL,
            SettingsKeys.warmthBias: 0.55,
            SettingsKeys.sadismBias: 0.55,
            SettingsKeys.intensityBias: 0.55,
            SettingsKeys.awayModel: SettingsKeys.defaultAwayModel,
        ])
        if let snapshot = SoulStore.load() {
            emotion = snapshot.emotion
            messages = snapshot.messages
        }
        // Republish the nested player's changes so bubbles update play state.
        voice.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Settings

    var macURLString: String {
        defaults.string(forKey: SettingsKeys.macURL) ?? SettingsKeys.defaultMacURL
    }
    private var userName: String { defaults.string(forKey: SettingsKeys.userName) ?? "" }
    private var notes: String { defaults.string(forKey: SettingsKeys.notes) ?? "" }
    private var warmthBias: Double { defaults.double(forKey: SettingsKeys.warmthBias) }
    private var sadismBias: Double { defaults.double(forKey: SettingsKeys.sadismBias) }
    private var intensityBias: Double { defaults.double(forKey: SettingsKeys.intensityBias) }
    private var awayModel: String {
        defaults.string(forKey: SettingsKeys.awayModel) ?? SettingsKeys.defaultAwayModel
    }
    private var xaiKey: String? {
        guard let key = Keychain.get(Keychain.xaiKeyAccount),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return key
    }

    // MARK: - Link state

    func refreshLink() async {
        mode = .checking
        if let link = MacLink(urlString: macURLString), await link.isAwake() {
            mode = .home
        } else if xaiKey != nil {
            mode = .away
        } else {
            mode = .offline
        }
    }

    // MARK: - Sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        let history = recentTurns()
        messages.append(ChatMessage(role: .user, text: text))
        isThinking = true
        Task {
            await deliver(text, history: history)
            isThinking = false
            persist()
        }
    }

    /// A finished mic take: transcribe it (Mac Whisper at home, on-device
    /// Whisper away — never Apple Speech), then send like typed text.
    func heard(_ fileURL: URL) {
        guard !isHearing else { return }
        isHearing = true
        hearingStatus = "hearing you…"
        Task {
            do {
                let text = try await transcribe(fileURL)
                isHearing = false
                hearingStatus = nil
                if text.isEmpty {
                    banner = "She didn't catch anything — try again."
                } else {
                    send(text)
                }
            } catch {
                isHearing = false
                hearingStatus = nil
                banner = "Couldn't transcribe — \(error.localizedDescription)"
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func transcribe(_ fileURL: URL) async throws -> String {
        if let link = MacLink(urlString: macURLString), await link.isAwake() {
            mode = .home
            do {
                return try await link.transcribe(fileURL: fileURL)
            } catch {
                banner = "Mac whisper failed — using on-device. (\(error.localizedDescription))"
            }
        }
        // Away (or Mac STT failed): on-device WhisperKit. Still no Apple Speech.
        return try await LocalWhisper.shared.transcribe(fileURL) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.hearingStatus = status
            }
        }
    }

    private func recentTurns() -> [Turn] {
        messages.suffix(24)
            .filter { !$0.isError }
            .map { Turn(role: $0.role.rawValue, content: $0.text) }
    }

    /// Prefer her home on the Mac; fall back to Grok direct when away.
    private func deliver(_ text: String, history: [Turn]) async {
        if let link = MacLink(urlString: macURLString), await link.isAwake() {
            mode = .home
            do {
                try await sendViaMac(link, text: text, history: history)
                return
            } catch VesperError.http(let code, _) where code == 404 {
                // Older phone API without /v1/chat/stream — one-shot chat.
                do {
                    try await sendViaMacLegacy(link, text: text, history: history)
                    return
                } catch {
                    banner = "Home leg failed — \(error.localizedDescription)"
                }
            } catch {
                banner = "Home leg failed — \(error.localizedDescription)"
            }
        }

        if let key = xaiKey {
            mode = .away
            do {
                try await sendViaXAI(key: key, text: text, history: history)
                return
            } catch {
                banner = error.localizedDescription
                appendQuiet(error)
            }
        } else {
            mode = .offline
            banner = "Her Mac is unreachable and no xAI key is saved — she can't hear you right now."
            appendQuiet(nil)
        }
    }

    /// Streaming home leg: tokens append live, her voice starts on the first
    /// sentence clip while the rest is still generating.
    private func sendViaMac(_ link: MacLink, text: String, history: [Turn]) async throws {
        let payload = macPayload(text: text, history: history)
        var replyID: UUID?
        var streamError: String?

        try await link.chatStream(payload) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case "state":
                if let state = event.state {
                    self.emotion = state
                }
            case "delta":
                guard let delta = event.text else { return }
                if let id = replyID {
                    self.mutateMessage(id) { $0.text += delta }
                } else {
                    let message = ChatMessage(role: .assistant, text: delta)
                    replyID = message.id
                    self.messages.append(message)
                    self.isThinking = false  // words are landing; drop the dots
                }
            case "audio":
                guard let id = replyID,
                      let b64 = event.audioB64,
                      let clip = Data(base64Encoded: b64)
                else { return }
                self.mutateMessage(id) { message in
                    var clips = message.audioClips ?? []
                    clips.append(clip)
                    message.audioClips = clips
                    message.audioSeconds =
                        (message.audioSeconds ?? 0) + (VoicePlayer.duration(of: clip) ?? 0)
                }
                self.voice.enqueue(clip, for: id)
            case "done":
                if let id = replyID, let full = event.reply {
                    self.mutateMessage(id) { $0.text = full }
                }
            case "error":
                streamError = event.detail ?? "the stream broke"
            default:
                break
            }
        }

        if replyID == nil {
            // Nothing rendered — surface the failure so deliver() can fall back.
            throw VesperError.http(502, streamError ?? "empty reply from the model")
        }
        if let streamError {
            banner = "Her voice trailed off — \(streamError)"
        }
    }

    /// Pre-streaming phone API (kept for older Macs): one-shot reply + clip.
    private func sendViaMacLegacy(_ link: MacLink, text: String, history: [Turn]) async throws {
        let response = try await link.chat(macPayload(text: text, history: history))
        emotion = response.state
        var audio: Data?
        if let b64 = response.audioB64 {
            audio = Data(base64Encoded: b64)
        }
        appendReply(response.reply, audio: audio)
    }

    private func macPayload(text: String, history: [Turn]) -> MacChatRequest {
        MacChatRequest(
            message: text,
            history: history,
            state: emotion,
            userName: userName,
            notes: notes,
            warmthBias: warmthBias,
            sadismBias: sadismBias,
            intensity: intensityBias,
            wantAudio: true
        )
    }

    private func mutateMessage(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        change(&message)
        messages[index] = message
    }

    private func sendViaXAI(key: String, text: String, history: [Turn]) async throws {
        // Same turn pipeline the Mac runs, mirrored on device.
        emotion.blendIntensity(toward: intensityBias)
        emotion.absorb(text, warmthBias: warmthBias, sadismBias: sadismBias)
        let system = Persona.systemPrompt(
            state: emotion, userName: userName, notes: notes, intensityBias: intensityBias
        )
        let xai = XAILink(apiKey: key, model: awayModel)
        let reply = try await xai.chat(system: system, history: history, user: text)
        let audio = try? await xai.speak(reply)
        appendReply(reply, audio: audio)
    }

    private func appendReply(_ text: String, audio: Data?) {
        var message = ChatMessage(role: .assistant, text: text, audio: audio)
        if let audio {
            message.audioSeconds = VoicePlayer.duration(of: audio)
        }
        messages.append(message)
        // Her voice plays itself, like a voice note — no transport controls.
        if let audio {
            voice.play(audio, id: message.id)
        }
    }

    private func appendQuiet(_ error: Error?) {
        var text = "*Vesper goes quiet for a moment.*"
        if let error {
            text += "\n\n\(error.localizedDescription)"
        }
        messages.append(ChatMessage(role: .assistant, text: text, isError: true))
    }

    // MARK: - Housekeeping

    func resetSoul() {
        voice.stop()
        messages = []
        emotion = EmotionState()
        SoulStore.wipe()
    }

    private func persist() {
        SoulStore.save(SoulSnapshot(emotion: emotion, messages: messages))
    }
}
