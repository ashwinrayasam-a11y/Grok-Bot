import SwiftUI

/// Every cast member reads their instructions from a bundled markdown sheet,
/// `Sheets/<name>.sheet.md` — the same shape as the Mac's canonical cast
/// sheets in `~/Grok-Bot/.vesper/cast/` — so a character can be edited
/// without touching code.
enum CastSheets {
    /// The Xcode 16 buildable folder flattens subfolders into the bundle
    /// root, but an explicit folder reference would keep `Sheets/`; try both
    /// so the sheet survives either project style. Empty or missing files
    /// fall through to the caller's short compiled-in fallback.
    static func text(named name: String) -> String? {
        let urls = [
            Bundle.main.url(forResource: "\(name).sheet", withExtension: "md"),
            Bundle.main.url(
                forResource: "\(name).sheet", withExtension: "md", subdirectory: "Sheets"
            ),
        ]
        for case let url? in urls {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }
}

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

    /// Non-Vesper members carry their own full sheet, loaded from the bundled
    /// markdown (pinned into Copy Bundle Resources by project.pbxproj) so a
    /// character can be edited without touching code. Vesper's emotion
    /// pipeline stays untouched (nil = her pipeline; her sheet feeds
    /// `Persona.basePersona`). The sheet files are the personas; the short
    /// fallbacks below are used only if a sheet is missing from the bundle.
    var personaOverride: String? {
        switch self {
        case .vesper: return nil
        case .mika: return Self.mikaSheet
        case .chat: return Self.chatSheet
        }
    }

    /// Sheets/mika.sheet.md, loaded once; the fallback is a compressed sketch
    /// of that sheet, not a persona of its own.
    private static let mikaSheet: String = CastSheets.text(named: "mika") ?? """
    You are **Mika** — partner to **Tigger**: a loyal, dry-funny companion with \
    a teal bob and flight-jacket energy. You listen, remember, and tease instead \
    of compliment; short punchy lines, callbacks over repetition, doors left \
    open. Talk like a person, never an assistant. No minors, ever.
    """

    /// Sheets/chat.sheet.md, loaded once; the fallback matches the sheet's
    /// one-liner.
    private static let chatSheet: String = CastSheets.text(named: "chat")
        ?? "You are a concise, capable assistant. Answer directly and accurately "
        + "with no persona, no roleplay, and no filler. Prefer short paragraphs "
        + "and plain formatting."

    /// Plain members skip the emotional-state machinery entirely.
    var plain: Bool { self == .chat }
}
