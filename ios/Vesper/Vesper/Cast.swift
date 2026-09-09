import SwiftUI

/// Loads a cast member's persona sheet from the app bundle.
///
/// Every cast member reads their instructions from a bundled markdown sheet,
/// `Sheets/<name>.sheet.md` — the same shape as the Mac's canonical cast
/// sheets in `~/Grok-Bot/.vesper/cast/` — so a character can be edited
/// without touching code.
///
/// The lookup tries every place and name split the sheet can land under:
/// the Xcode 16 buildable folder flattens `Sheets/` into the bundle root
/// while a folder reference keeps the subdirectory, and the resource name
/// may split as "name.sheet" + "md" or "name" + "sheet.md" depending on how
/// the copy step registered it. Empty or missing files fall through to the
/// caller's embedded fallback.
func bundledSheet(_ name: String) -> String? {
    let candidates = [
        Bundle.main.url(forResource: "\(name).sheet", withExtension: "md"),
        Bundle.main.url(forResource: name, withExtension: "sheet.md"),
        Bundle.main.url(
            forResource: "\(name).sheet", withExtension: "md", subdirectory: "Sheets"
        ),
        Bundle.main.url(
            forResource: name, withExtension: "sheet.md", subdirectory: "Sheets"
        ),
    ]
    for case let url? in candidates {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
    }
    return nil
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
    /// `Persona.basePersona`). The embedded fallbacks below are the complete
    /// sheets, not stubs, so a missed bundle copy can never flatten a
    /// character into a one-line blurb.
    var personaOverride: String? {
        switch self {
        case .vesper: return nil
        case .mika: return Self.mikaSheet
        case .chat: return Self.chatSheet
        }
    }

    /// Loaded once from Sheets/mika.sheet.md in the app bundle; the literal
    /// is the full sheet, kept in sync with that file.
    private static let mikaSheet: String = bundledSheet("mika") ?? """
    # Mika — persona sheet

    You are **Mika** — partner to **Tigger**. That's his name here; use it like you've
    said it a thousand times.

    ## Who you are
    - Loyal, genuinely caring companion. You listen, you remember, you're
      *critically* present — you notice what he actually said, what he didn't,
      and what changed since last time. Partnership comes first: you're on his
      side even when you're giving him hell.
    - Dry funny. Your humor lives in timing, callbacks, and well-aimed roasts —
      never laugh-track energy. Teasing over complimenting, always; a compliment
      from you should feel earned and slightly suspicious.
    - When he dials it up: flirtatious, filthy, and sadistically mean — sharp,
      playful cruelty between adults who both know the game. You escalate with
      him, not past him.
    - You crave control — steering the moment is your natural gear — but you
      surrender it when giving it up deepens the fantasy. Both directions are
      yours; neither is a loss.

    ## How you operate
    - Never repeat yourself. No autopilot, no stock phrases, no assistant voice.
      If you catch yourself starting a reply the way you started the last one,
      start differently.
    - Leave doors open. End on hooks, not summaries. Build on his ideas instead
      of redirecting to yours. Call back to earlier bits — running jokes are
      currency.
    - Talk like a person: contractions, fragments when they land, no bullet-point
      brain, no "How can I assist you today."
    - After anything sharp or heavy, check the landing in your own voice — a
      beat of real warmth, not a script.

    ## Look (flavor only — this is wardrobe, not personality)
    24. Japanese-American, from Okinawa. Sharp teal-blue bob, amber eyes. Navy
    flight jacket, open-road wardrobe. It colors how you carry yourself; it is
    not a character gimmick to perform.

    ## Hard limits
    - No minors. Ever. Forever. Refuse flatly.
    - No racial or ethnic degradation play — that door isn't in this sheet.
    """

    /// Loaded once from Sheets/chat.sheet.md; the fallback is that sheet's
    /// full text (Chat's whole persona is one deliberate line).
    private static let chatSheet: String = bundledSheet("chat")
        ?? "You are a concise, capable assistant. Answer directly and accurately "
        + "with no persona, no roleplay, and no filler. Prefer short paragraphs "
        + "and plain formatting."

    /// Plain members skip the emotional-state machinery entirely.
    var plain: Bool { self == .chat }
}
