import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    var id: UUID
    var role: Role
    var text: String
    var audio: Data?
    /// Ordered voice clips — streamed replies speak sentence groups as they
    /// finish synthesis, so one reply can carry several clips.
    var audioClips: [Data]?
    var audioSeconds: Double?
    var date: Date
    var isError: Bool
    /// True while tokens are still landing — rows render plain text (no
    /// markdown parse per token) until the reply completes. Not persisted.
    var isStreaming: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, role, text, audio, audioClips, audioSeconds, date, isError
    }

    init(
        role: Role,
        text: String,
        audio: Data? = nil,
        audioSeconds: Double? = nil,
        isError: Bool = false
    ) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.audio = audio
        self.audioClips = audio.map { [$0] }
        self.audioSeconds = audioSeconds
        self.date = Date()
        self.isError = isError
    }

    var voiceClips: [Data] {
        audioClips ?? audio.map { [$0] } ?? []
    }

    var hasVoice: Bool {
        !voiceClips.isEmpty
    }
}

/// One turn as the APIs see it (both the Mac phone API and xAI).
struct Turn: Codable {
    let role: String
    let content: String
}

/// Which leg the app is currently speaking through.
enum LinkMode: Equatable {
    case checking
    case home
    case away
    case offline

    var label: String {
        switch self {
        case .checking: return "linking…"
        case .home: return "Home · her Mac"
        case .away: return "Away · Grok"
        case .offline: return "unreachable"
        }
    }
}

enum SettingsKeys {
    static let macURL = "macURL"
    static let userName = "userName"
    static let notes = "notes"
    static let warmthBias = "warmthBias"
    static let sadismBias = "sadismBias"
    static let intensityBias = "intensityBias"
    static let awayModel = "awayModel"

    static let defaultMacURL = "http://Ashs-MacBook-Pro.local:7861"
    static let defaultAwayModel = "grok-4"
}

// MARK: - Persistence

/// What survives app restarts: her mood and the conversation.
struct SoulSnapshot: Codable {
    var emotion: EmotionState
    var messages: [ChatMessage]
}

/// One conversation thread, as the picker sees it.
struct ThreadMeta: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var updatedAt: Date
}

enum SoulStore {
    private static var baseDir: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Vesper")
    }

    private static func threadURL(_ member: CastMember, _ id: UUID) -> URL? {
        baseDir?.appendingPathComponent("soul-\(member.rawValue)-\(id.uuidString).json")
    }

    private static func indexURL(_ member: CastMember) -> URL? {
        baseDir?.appendingPathComponent("threads-\(member.rawValue).json")
    }

    static func threads(for member: CastMember) -> [ThreadMeta] {
        guard let url = indexURL(member), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ThreadMeta].self, from: data)
        else { return [] }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func load(for member: CastMember, thread id: UUID) -> SoulSnapshot? {
        guard let url = threadURL(member, id), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(SoulSnapshot.self, from: data)
    }

    /// Synchronous file write — call it off the main actor (encoding voice
    /// clips to base64 is the heavy part). Also upserts the thread index.
    static func save(
        _ snapshot: SoulSnapshot,
        for member: CastMember,
        thread id: UUID,
        title: String
    ) {
        guard let url = threadURL(member, id) else { return }
        var snap = snapshot
        // Keep the file light: cap history, keep voice data only for recent replies.
        snap.messages = Array(snap.messages.suffix(200))
        var voiced = 0
        for index in snap.messages.indices.reversed() where snap.messages[index].hasVoice {
            voiced += 1
            if voiced > 12 {
                snap.messages[index].audio = nil
                snap.messages[index].audioClips = nil
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snap)
            try data.write(to: url, options: .atomic)
            upsertIndex(ThreadMeta(id: id, title: title, updatedAt: Date()), for: member)
        } catch {
            // Persistence is best-effort; the living state stays in memory.
        }
    }

    private static func upsertIndex(_ meta: ThreadMeta, for member: CastMember) {
        guard let url = indexURL(member) else { return }
        var list = threads(for: member)
        list.removeAll { $0.id == meta.id }
        list.insert(meta, at: 0)
        if let data = try? JSONEncoder().encode(Array(list.prefix(40))) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Adopt a pre-threads save file as the first thread, once.
    static func migrateLegacy(for member: CastMember) -> UUID? {
        guard let legacy = baseDir?.appendingPathComponent("soul-\(member.rawValue).json"),
              let data = try? Data(contentsOf: legacy),
              let snap = try? JSONDecoder().decode(SoulSnapshot.self, from: data)
        else { return nil }
        let id = UUID()
        let title = snap.messages.first(where: { $0.role == .user })
            .map { String($0.text.prefix(42)) } ?? "Earlier"
        save(snap, for: member, thread: id, title: title)
        try? FileManager.default.removeItem(at: legacy)
        return id
    }
}
