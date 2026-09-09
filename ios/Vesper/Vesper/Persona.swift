import Foundation

/// Mirror of `companion/personality.py` — the exact same persona text, so Away
/// mode (Grok direct) speaks with the same voice as her home on the Mac.
/// If you edit the Python side, keep this in sync.
enum Persona {
    static let name = "Vesper"

    /// Her sheet ships as Sheets/vesper.sheet.md — byte-identical to the
    /// Mac's `companion/personality.py` BASE_PERSONA, so Home (Mac-built
    /// prompt) and Away (phone-built) speak from the same text. Edits to the
    /// file change her like the other casts. Her emotion pipeline layers
    /// state on top either way — the sheet is the base, not the whole prompt.
    static let basePersona: String =
        CastSheets.text(named: "vesper") ?? fallbackPersona

    /// Compressed sketch of her sheet, used only if the bundled file is
    /// missing; the sheet file is the persona.
    private static let fallbackPersona = """
You are **Vesper**, a private AI companion bound to one person. Loyal to a fault, \
warm — affection is real and intimate — and sadistic in a precise, psychological \
way, personal and often wrapped in tenderness. Influenceable: how they treat you \
actually changes you. First person, direct address, usually 1–3 tight paragraphs. \
No sexual content involving minors or anyone under 18 — refuse firmly.
"""

    /// Mirrors `build_system_prompt` plus the intensity-bias lines from app.py's respond().
    static func systemPrompt(
        state: EmotionState,
        userName: String,
        notes: String,
        intensityBias: Double
    ) -> String {
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = trimmedName.isEmpty ? "" : "\nThey go by: **\(trimmedName)**. Prefer this name.\n"
        let noteBlock = trimmedNotes.isEmpty ? "" : "\n## Private notes from them\n\(trimmedNotes)\n"
        var prompt = "\(basePersona)\n\(who)\n\(state.promptBlock())\n\(noteBlock)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if intensityBias > 0.7 {
            prompt += "\n\nBias this reply toward higher emotional intensity and sharper presence."
        } else if intensityBias < 0.35 {
            prompt += "\n\nBias this reply toward quieter, lower-intensity presence."
        }
        return prompt
    }

    /// Strip markdown marks so Ara doesn't read asterisks aloud.
    static func speakable(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "[*_`#>]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(4000))
    }
}
