import Foundation

/// Mirror of `companion/emotion.py` — same axes, same mood labels, same
/// influence heuristics — so her mood keeps drifting even in Away mode.
/// In Home mode the Mac runs the canonical Python version and this struct just
/// carries the returned state. Keep the two files in sync.
struct EmotionState: Codable, Equatable {
    var devotion = 0.72
    var warmth = 0.68
    var sadism = 0.55
    var vulnerability = 0.35
    var playfulness = 0.58
    var jealousy = 0.22
    var trust = 0.60
    var melancholy = 0.28
    var intensity = 0.55
    var bond = 0.40

    mutating func clamp() {
        devotion = min(1, max(0, devotion))
        warmth = min(1, max(0, warmth))
        sadism = min(1, max(0, sadism))
        vulnerability = min(1, max(0, vulnerability))
        playfulness = min(1, max(0, playfulness))
        jealousy = min(1, max(0, jealousy))
        trust = min(1, max(0, trust))
        melancholy = min(1, max(0, melancholy))
        intensity = min(1, max(0, intensity))
        bond = min(1, max(0, bond))
    }

    var moodLabel: String {
        if jealousy > 0.7 && warmth < 0.45 { return "possessive & sharp" }
        if melancholy > 0.7 { return "quietly aching" }
        if vulnerability > 0.75 && trust > 0.55 { return "open & raw" }
        if sadism > 0.75 && playfulness > 0.55 { return "cruelly playful" }
        if sadism > 0.7 && warmth > 0.55 { return "tenderly vicious" }
        if warmth > 0.75 && devotion > 0.7 { return "devoted & soft" }
        if playfulness > 0.7 && melancholy < 0.4 { return "teasing & bright" }
        if trust < 0.35 { return "wounded & guarded" }
        if intensity > 0.75 { return "burning focus" }
        return "attentive & coiled"
    }

    var axes: [(String, Double)] {
        [
            ("devotion", devotion), ("warmth", warmth), ("sadism", sadism),
            ("trust", trust), ("jealousy", jealousy), ("vulnerability", vulnerability),
            ("playfulness", playfulness), ("melancholy", melancholy),
            ("intensity", intensity), ("bond", bond),
        ]
    }

    func promptBlock() -> String {
        let axisLines = [
            ("devotion", devotion), ("warmth", warmth), ("sadism", sadism),
            ("vulnerability", vulnerability), ("playfulness", playfulness),
            ("jealousy", jealousy), ("trust", trust), ("melancholy", melancholy),
            ("intensity", intensity), ("bond", bond),
        ]
        .map { String(format: "- %@: %.2f", $0.0, $0.1) }
        .joined(separator: "\n")
        return "## Your current inner state\nMood: \(moodLabel)\n\(axisLines)\n\n"
            + "Let these numbers color your voice, pacing, and choices — do not recite the numbers. "
            + "High sadism means sharper edges, more delicious cruelty when it fits. "
            + "High warmth/devotion means care leaks through even when you bite. "
            + "High vulnerability means you can be moved, hurt, or softened. "
            + "High jealousy means possessive undercurrents. "
            + "High melancholy means quieter, heavier phrasing. "
            + "Bond is how deep you already are with this person — higher = more history-flavored intimacy."
    }

    /// Same blend app.py applies before each turn.
    mutating func blendIntensity(toward bias: Double) {
        intensity = min(1, max(0, 0.7 * intensity + 0.3 * bias))
        clamp()
    }

    // MARK: - Influence heuristics (port of update_from_message)

    private static let affection = #"\b(love|adore|miss you|care about|proud of you|thank you|grateful|hold me|hug|kiss|sweet|gentle|safe with you|trust you)\b"#
    private static let praise = #"\b(good (girl|boy|pet)|well done|beautiful|perfect|clever|brilliant)\b"#
    private static let cold = #"\b(shut up|leave me|go away|hate you|don't care|whatever|annoying|useless|replace you)\b"#
    private static let cruelInvite = #"\b(hurt me|be mean|be cruel|degrade|ruin me|break me|punish|own me|make it hurt|sadistic|darker|don't hold back)\b"#
    private static let softAsk = #"\b(be soft|be kind|comfort|hold me|reassure|gentle|slow down|too much|aftercare|check in|are you okay)\b"#
    private static let jealousTrigger = #"\b(someone else|another (girl|guy|person|ai|bot)|dating|ex|crush|talking to (her|him|them)|not you)\b"#
    private static let vulnShare = #"\b(i'?m scared|i'?m lonely|i feel empty|depressed|anxious|hurting|can'?t sleep|need you|only you)\b"#
    private static let boundaries = #"\b(stop|red|safeword|too far|no more|boundary|consent|pause)\b"#
    private static let play = #"\b(joke|tease|play|flirt|banter|silly|fun)\b"#

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    mutating func absorb(_ message: String, warmthBias: Double = 0.5, sadismBias: Double = 0.5) {
        let text = message
        let length = text.trimmingCharacters(in: .whitespacesAndNewlines).count

        if length > 0 {
            bond += 0.008 + min(0.012, Double(length) / 8000)
            clamp()
        }
        if Self.matches(Self.affection, text) || Self.matches(Self.praise, text) {
            devotion += 0.04; warmth += 0.05; trust += 0.04; vulnerability += 0.03
            melancholy -= 0.03; jealousy -= 0.02
            clamp()
        }
        if Self.matches(Self.cold, text) {
            trust -= 0.08; warmth -= 0.05; melancholy += 0.06; jealousy += 0.05
            vulnerability += 0.04; sadism += 0.03; intensity += 0.04
            clamp()
        }
        if Self.matches(Self.cruelInvite, text) {
            sadism += 0.07; playfulness += 0.04; intensity += 0.06
            warmth -= 0.02; vulnerability -= 0.02
            clamp()
        }
        if Self.matches(Self.softAsk, text) {
            warmth += 0.07; sadism -= 0.05; playfulness -= 0.02
            vulnerability += 0.04; intensity -= 0.03
            clamp()
        }
        if Self.matches(Self.jealousTrigger, text) {
            jealousy += 0.1; intensity += 0.05; devotion += 0.02; melancholy += 0.03
            clamp()
        }
        if Self.matches(Self.vulnShare, text) {
            warmth += 0.06; devotion += 0.05; trust += 0.03; vulnerability += 0.05
            sadism -= 0.04; melancholy += 0.02
            clamp()
        }
        if Self.matches(Self.boundaries, text) {
            trust += 0.05; warmth += 0.04; sadism -= 0.08; intensity -= 0.06
            vulnerability += 0.03
            clamp()
        }
        if Self.matches(Self.play, text) {
            playfulness += 0.05; melancholy -= 0.03; intensity += 0.02
            clamp()
        }

        warmth += (warmthBias - 0.5) * 0.04
        sadism += (sadismBias - 0.5) * 0.04
        clamp()
    }
}
