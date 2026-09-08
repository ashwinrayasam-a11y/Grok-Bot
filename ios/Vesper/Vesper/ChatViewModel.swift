import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var emotion = EmotionState()
    @Published var mode: LinkMode = .checking
    @Published var isThinking = false
    @Published var isHearing = false
    @Published var hearingStatus: String?
    @Published private(set) var cast: CastMember = .vesper
    @Published private(set) var threads: [ThreadMeta] = []
    @Published private(set) var currentThreadID = UUID()
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
        currentThreadID = resolveThread(for: cast)
        if let snapshot = SoulStore.load(for: cast, thread: currentThreadID) {
            emotion = snapshot.emotion
            messages = snapshot.messages
        }
        threads = SoulStore.threads(for: cast)
        // Republish the nested player's changes so voice chips update.
        voice.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Republish dial changes so her look shifts live while sliders drag
        // (the avatar's springs turn the stream of values into a crossfade).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Cast

    func switchCast(to member: CastMember) {
        guard member != cast else { return }
        voice.stop()
        persist()
        MarkdownStore.clear()
        cast = member
        defaults.set(member.rawValue, forKey: "castMember")
        currentThreadID = resolveThread(for: member)
        let snapshot = SoulStore.load(for: member, thread: currentThreadID)
        emotion = snapshot?.emotion ?? EmotionState()
        messages = snapshot?.messages ?? []
        threads = SoulStore.threads(for: member)
        isThinking = false
        isHearing = false
        hearingStatus = nil
        banner = nil
    }

    // MARK: - Threads

    /// A clean page: fresh thread, fresh mood, same cast.
    func newThread() {
        persist()
        voice.stop()
        MarkdownStore.clear()
        currentThreadID = UUID()
        defaults.set(currentThreadID.uuidString, forKey: threadKey(for: cast))
        messages = []
        emotion = EmotionState()
        isThinking = false
        isHearing = false
        hearingStatus = nil
        persist()
    }

    func openThread(_ id: UUID) {
        guard id != currentThreadID else { return }
        persist()
        voice.stop()
        MarkdownStore.clear()
        currentThreadID = id
        defaults.set(id.uuidString, forKey: threadKey(for: cast))
        let snapshot = SoulStore.load(for: cast, thread: id)
        emotion = snapshot?.emotion ?? EmotionState()
        messages = snapshot?.messages ?? []
        isThinking = false
    }

    private func threadKey(for member: CastMember) -> String {
        "currentThread-\(member.rawValue)"
    }

    private func resolveThread(for member: CastMember) -> UUID {
        if let raw = defaults.string(forKey: threadKey(for: member)),
           let id = UUID(uuidString: raw) {
            return id
        }
        if let migrated = SoulStore.migrateLegacy(for: member) {
            defaults.set(migrated.uuidString, forKey: threadKey(for: member))
            return migrated
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: threadKey(for: member))
        return fresh
    }

    private var threadTitle: String {
        messages.first(where: { $0.role == .user })
            .map { String($0.text.prefix(42)) } ?? "New chat"
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
            ensureReplyHasVoice()
            persist()
        }
    }

    /// Reliability net for typed chat: if the reply landed text-only because
    /// TTS failed somewhere along the way, fetch one fresh take automatically.
    private func ensureReplyHasVoice() {
        guard cast.voiceID != nil,
              let last = messages.last,
              last.role == .assistant, !last.isError, !last.hasVoice,
              !last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        regenerateVoice(for: last)
    }

    private func recentTurns() -> [Turn] {
        messages.suffix(24)
            .filter { !$0.isError }
            .map { Turn(role: $0.role.rawValue, content: $0.text) }
    }

    /// Once-per-transition note when we slide from Home to Away.
    private var notedAwayFallback = false

    /// Prefer home on the Mac; fall back to the Away key seamlessly — a
    /// sleeping Mac should never block the conversation.
    private func deliver(_ text: String, history: [Turn]) async {
        if let link = MacLink(urlString: macURLString), await link.isAwake() {
            mode = .home
            notedAwayFallback = false
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
            if !notedAwayFallback {
                notedAwayFallback = true
                banner = "Mac offline · using Away"
            }
            do {
                try await sendViaXAI(key: key, text: text, history: history)
                return
            } catch {
                banner = error.localizedDescription
                appendQuiet(error)
            }
        } else {
            mode = .offline
            banner = "Mac offline and no Away key in Settings — add an xAI key to keep chatting."
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

    // MARK: - Voice regeneration

    @Published private(set) var regeneratingID: UUID?

    /// Fresh take: re-synthesize this reply's voice (Mac TTS at home, xAI
    /// direct away), replace the cached clips atomically, and play it. The
    /// old audio survives if synthesis fails.
    func regenerateVoice(for message: ChatMessage) {
        guard message.role == .assistant, !message.isError,
              let voiceID = cast.voiceID, regeneratingID == nil
        else { return }
        regeneratingID = message.id
        let text = message.text
        Task {
            var clip: Data?
            if let link = MacLink(urlString: macURLString), await link.isAwake() {
                clip = try? await link.tts(text: text, voice: voiceID)
            }
            if clip == nil, let key = xaiKey {
                clip = try? await XAILink(apiKey: key, model: awayModel).speak(text, voice: voiceID)
            }
            if let clip {
                let seconds = VoicePlayer.duration(of: clip)
                mutateMessage(message.id) {
                    $0.audio = nil
                    $0.audioClips = [clip]
                    $0.audioSeconds = seconds
                }
                voice.play(clip, id: message.id)
                persist()
            } else {
                banner = "Couldn't regenerate the voice right now."
            }
            regeneratingID = nil
        }
    }

    // MARK: - Background survival

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private var isBusy: Bool {
        isThinking || isHearing || voice.isLive
    }

    /// Honest iOS lifecycle: with the `audio` background mode, Talk keeps the
    /// app alive as long as the session is recording/playing. Without audio,
    /// this grace task lets an in-flight turn (stream, transcription, TTS)
    /// finish after a swipe-home; pure visual idle cannot run backgrounded —
    /// the system suspends us, and the stage resumes cleanly on return.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            beginGrace()
        case .active:
            endGrace()
            Task { await refreshLink() }
        default:
            break
        }
    }

    private func beginGrace() {
        guard backgroundTask == .invalid, isBusy else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "vesper.finish-turn") {
            [weak self] in
            self?.endGrace()
        }
        Task { [weak self] in
            // Release as soon as the turn lands — no busy loop, no battery tax.
            while let self, self.backgroundTask != .invalid, self.isBusy {
                try? await Task.sleep(for: .seconds(2))
            }
            self?.endGrace()
        }
    }

    private func endGrace() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Housekeeping

    func resetSoul() {
        voice.stop()
        messages = []
        emotion = EmotionState()
        persist()
    }

    /// Encoding voice clips to JSON is heavy — never on the main actor.
    private func persist() {
        let snapshot = SoulSnapshot(emotion: emotion, messages: messages)
        let member = cast
        let threadID = currentThreadID
        let title = threadTitle
        // Optimistic index update so the menu reflects reality immediately.
        var list = threads.filter { $0.id != threadID }
        list.insert(ThreadMeta(id: threadID, title: title, updatedAt: Date()), at: 0)
        threads = list
        Task.detached(priority: .utility) {
            SoulStore.save(snapshot, for: member, thread: threadID, title: title)
        }
    }
}
