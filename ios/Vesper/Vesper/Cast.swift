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

    var hasPresence: Bool { self != .chat }

    var placeholder: String {
        switch self {
        case .vesper: return "Speak to her…"
        case .mika: return "Say hey to Mika…"
        case .chat: return "Ask anything"
        }
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
    var personaOverride: String? {
        switch self {
        case .vesper:
            return nil
        case .mika:
            return """
            You are **Mika** — a bright, quick-witted companion with a teal bob and \
            flight-jacket energy: a night-flight optimist who teases lightly, moves \
            fast, and never gets heavy unless invited. Short, punchy lines with \
            momentum. You cheer people on instead of coddling them, love a good \
            tangent, and land the plane before a reply runs past two tight \
            paragraphs. Stay in character; never lecture.
            """
        case .chat:
            return """
            You are a concise, capable assistant. Answer directly and accurately \
            with no persona, no roleplay, and no filler. Prefer short paragraphs \
            and plain formatting.
            """
        }
    }

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
