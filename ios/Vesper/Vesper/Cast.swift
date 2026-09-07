import SwiftUI

/// The whole cast: three, no more. Each member owns a world — accent, copy,
/// voice, persona, backdrop — so switching feels like entering their page,
/// not re-skinning a template.
enum CastMember: String, CaseIterable, Identifiable, Codable {
    case vesper
    case mika
    case chat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vesper: return "Vesper"
        case .mika: return "Mika"
        case .chat: return "Chat"
        }
    }

    /// One restrained accent each — no neon rainbow.
    var accent: Color {
        switch self {
        case .vesper: return Color(hex: 0xC4703A)  // warm ember
        case .mika: return Color(hex: 0x3FB8B2)    // jet-stream teal
        case .chat: return Color(hex: 0xE8E4DE)    // soft white
        }
    }

    /// Presence is procedural-only by design: the 3D rig with per-member
    /// motion temperament. Video idle loops are explicitly rejected (the
    /// grainy Grok-export experiment), and nothing here depends on Grok's
    /// live companion pipeline — only documented xAI APIs for voice.
    var hasPresence: Bool { self != .chat }

    var placeholder: String {
        "Message \(displayName)"
    }

    var emptyTitle: String {
        switch self {
        case .vesper: return "She's already listening."
        case .mika: return "Wheels up whenever you are."
        case .chat: return "What do you need?"
        }
    }

    var emptyLine: String {
        switch self {
        case .vesper: return "Say something. The night is hers."
        case .mika: return "Quick question, long story, bad joke — all flyable."
        case .chat: return "Plain answers. No theater."
        }
    }

    /// xAI TTS voice; nil = text only.
    var voiceID: String? {
        switch self {
        case .vesper: return "ara"
        case .mika: return "eve"
        case .chat: return nil
        }
    }

    /// Non-Vesper members carry their own compact prompt. Vesper's full
    /// persona + emotion system stays untouched (nil = her pipeline).
    /// Mika's sheet ships as a bundled markdown file so it can be edited
    /// without touching code; the inline text is the fallback.
    var personaOverride: String? {
        switch self {
        case .vesper:
            return nil
        case .mika:
            return Self.mikaSheet ?? """
            You are **Mika** — a loyal, dry-funny companion with a teal bob and \
            flight-jacket energy. You listen, remember, and tease instead of \
            compliment; short punchy lines, callbacks over repetition, doors \
            left open. Talk like a person, never an assistant. No minors, ever.
            """
        case .chat:
            return """
            You are a concise, capable assistant. Answer directly and accurately \
            with no persona, no roleplay, and no filler. Prefer short paragraphs \
            and plain formatting.
            """
        }
    }

    /// Loaded once from Sheets/mika.sheet.md in the app bundle.
    private static let mikaSheet: String? = {
        guard let url = Bundle.main.url(forResource: "mika.sheet", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }()

    /// Plain members skip the emotional-state machinery entirely.
    var plain: Bool { self == .chat }

    /// Fixed mood biases for Mika's presence (Vesper uses her living state;
    /// this only colors the avatar's idle motion, never the text).
    var fixedEmotion: EmotionState? {
        guard self == .mika else { return nil }
        var e = EmotionState()
        e.playfulness = 0.85
        e.warmth = 0.7
        e.sadism = 0.08
        e.jealousy = 0.08
        e.melancholy = 0.1
        e.intensity = 0.5
        return e
    }
}
