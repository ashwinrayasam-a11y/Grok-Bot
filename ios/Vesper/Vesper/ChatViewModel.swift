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
    @Published private(set) var cast: CastMember = .vesper
    /// Bumped (throttled) while tokens stream so the view can follow the text
    /// without issuing a scroll command per token.
    @Published private(set) var scrollPulse = 0
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
    private var lastScrollPulse = Date.distantPast
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            SettingsKeys.macURL: SettingsKeys.defaultMacURL,
            SettingsKeys.warmthBias: 0.55,
            SettingsKeys.sadismBias: 0.55,
            SettingsKeys.intensityBias: 0.55,
            SettingsKeys.awayModel: SettingsKeys.defaultAwayModel,
        ])
        if let raw = defaults.string(forKey: "castMember"),
           let saved = CastMember(rawValue: raw) {
            cast = saved
        }
        if let snapshot = SoulStore.load(for: cast) {
            emotion = snapshot.emotion
            messages = snapshot.messages
        }
        // Republish the nested player's changes so voice chips update.
        voice.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Cast

    /// The emotion that colors the avatar's idle motion. Vesper is alive;
    /// Mika holds her own fixed temperament; Chat has no presence at all.
    var presenceEmotion: EmotionState {
        cast.fixedEmotion ?? emotion
    }

    func switchCast(to member: CastMember) {
        guard member != cast else { return }
        voice.stop()
        persist()
        cast = member
        defaults.set(member.rawValue, forKey: "castMember")
        let snapshot = SoulStore.load(for: member)
        emotion = snapshot?.emotion ?? EmotionState()
        messages = snapshot?.messages ?? []
        isThinking = false
        isHearing = false
        hearingStatus = nil
        banner = nil
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

    // MARK: - Voice input

    /// A finished mic take: transcribe (Mac Whisper at home, on-device
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
                    banner = "Didn't catch anything — try again."
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
        return try await LocalWhisper.shared.transcribe(fileURL) { [weak self] status in
            Task { @MainActor [weak self] in
                self?.hearingStatus = status
            }
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

    private func recentTurns() -> [Turn] {
        messages.suffix(24)
            .filter { !$0.isError }
            .map { Turn(role: $0.role.rawValue, content: $0.text) }
    }

    /// Prefer home on the Mac; fall back to Grok direct when away.
    private func deliver(_ text: String, history: [Turn]) async {
        if let link = MacLink(urlString: macURLString), await link.isAwake() {
            mode = .home
            do {
                try await sendViaMac(link, text: text, history: history)
                return
            } catch VesperError.http(let code, _) where code == 404 {
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
            banner = "The Mac is unreachable and no xAI key is saved."
            appendQuiet(nil)
        }
    }

    /// Streaming home leg: tokens append live; voice starts on the first clip.
    private func sendViaMac(_ link: MacLink, text: String, history: [Turn]) async throws {
        let payload = macPayload(text: text, history: history)
        var replyID: UUID?
        var streamError: String?

        try await link.chatStream(payload) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case "state":
                if self.cast == .vesper, let state = event.state {
                    self.emotion = state
                }
            case "delta":
                guard let delta = event.text else { return }
                if let id = replyID {
                    self.mutateMessage(id) { $0.text += delta }
                } else {
                    var message = ChatMessage(role: .assistant, text: delta)
                    message.isStreaming = true
                    replyID = message.id
                    self.messages.append(message)
                    self.isThinking = false
                }
                self.bumpScroll()
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
                if let id = replyID {
                    self.mutateMessage(id) {
                        if let full = event.reply { $0.text = full }
                        $0.isStreaming = false
                    }
                    self.scrollPulse += 1
                }
            case "error":
                streamError = event.detail ?? "the stream broke"
            default:
                break
            }
        }

        if let id = replyID {
            mutateMessage(id) { $0.isStreaming = false }
        } else {
            throw VesperError.http(502, streamError ?? "empty reply from the model")
        }
        if let streamError {
            banner = "The stream trailed off — \(streamError)"
        }
    }

    /// Pre-streaming phone API (older Macs): one-shot reply + clip.
    private func sendViaMacLegacy(_ link: MacLink, text: String, history: [Turn]) async throws {
        let response = try await link.chat(macPayload(text: text, history: history))
        if cast == .vesper {
            emotion = response.state
        }
        var audio: Data?
        if let b64 = response.audioB64 {
            audio = Data(base64Encoded: b64)
        }
        appendReply(response.reply, audio: audio)
    }

    private func sendViaXAI(key: String, text: String, history: [Turn]) async throws {
        let system: String
        if let override = cast.personaOverride {
            system = override
        } else {
            // Vesper: same turn pipeline the Mac runs, mirrored on device.
            emotion.blendIntensity(toward: intensityBias)
            emotion.absorb(text, warmthBias: warmthBias, sadismBias: sadismBias)
            system = Persona.systemPrompt(
                state: emotion, userName: userName, notes: notes, intensityBias: intensityBias
            )
        }
        let xai = XAILink(apiKey: key, model: awayModel)
        let reply = try await xai.chat(system: system, history: history, user: text)
        var audio: Data?
        if let voiceID = cast.voiceID {
            audio = try? await xai.speak(reply, voice: voiceID)
        }
        appendReply(reply, audio: audio)
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
            wantAudio: cast.voiceID != nil,
            personaOverride: cast.personaOverride,
            plain: cast.plain,
            voice: cast.voiceID
        )
    }

    private func mutateMessage(_ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        change(&message)
        messages[index] = message
    }

    /// At most ~8 scroll commands a second while tokens stream.
    private func bumpScroll() {
        let now = Date()
        if now.timeIntervalSince(lastScrollPulse) > 0.12 {
            lastScrollPulse = now
            scrollPulse += 1
        }
    }

    private func appendReply(_ text: String, audio: Data?) {
        var message = ChatMessage(role: .assistant, text: text, audio: audio)
        if let audio {
            message.audioSeconds = VoicePlayer.duration(of: audio)
        }
        messages.append(message)
        if let audio {
            voice.play(audio, id: message.id)
        }
    }

    private func appendQuiet(_ error: Error?) {
        var text = cast == .vesper
            ? "*Vesper goes quiet for a moment.*"
            : "No connection right now."
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
        SoulStore.wipe(for: cast)
    }

    /// Encoding voice clips to JSON is heavy — never on the main actor.
    private func persist() {
        let snapshot = SoulSnapshot(emotion: emotion, messages: messages)
        let member = cast
        Task.detached(priority: .utility) {
            SoulStore.save(snapshot, for: member)
        }
    }
}
