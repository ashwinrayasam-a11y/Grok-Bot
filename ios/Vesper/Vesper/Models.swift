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
    var audioSeconds: Double?
    var date: Date
    var isError: Bool

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
        self.audioSeconds = audioSeconds
        self.date = Date()
        self.isError = isError
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
    static let autoplay = "autoplay"
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

enum SoulStore {
    private static var fileURL: URL? {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return nil }
        return base.appendingPathComponent("Vesper/soul.json")
    }

    static func load() -> SoulSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SoulSnapshot.self, from: data)
    }

    static func save(_ snapshot: SoulSnapshot) {
        guard let url = fileURL else { return }
        var snap = snapshot
        // Keep the file light: cap history, keep voice data only for recent replies.
        snap.messages = Array(snap.messages.suffix(200))
        var voiced = 0
        for index in snap.messages.indices.reversed() where snap.messages[index].audio != nil {
            voiced += 1
            if voiced > 12 {
                snap.messages[index].audio = nil
            }
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snap)
            try data.write(to: url, options: .atomic)
        } catch {
            // Persistence is best-effort; the living state stays in memory.
        }
    }

    static func wipe() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
