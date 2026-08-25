import Combine
import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var emotion = EmotionState()
    @Published var mode: LinkMode = .checking
    @Published var isThinking = false
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
            SettingsKeys.autoplay: true,
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
    private var autoplay: Bool { defaults.bool(forKey: SettingsKeys.autoplay) }
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

    private func sendViaMac(_ link: MacLink, text: String, history: [Turn]) async throws {
        let payload = MacChatRequest(
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
        let response = try await link.chat(payload)
        emotion = response.state
        var audio: Data?
        if let b64 = response.audioB64 {
            audio = Data(base64Encoded: b64)
        }
        appendReply(response.reply, audio: audio)
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
        if autoplay, let audio {
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
