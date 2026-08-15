"""Living emotional state that drifts with how the user treats Vesper."""

from __future__ import annotations

from dataclasses import asdict, dataclass, fields
import re
from typing import Any


@dataclass
class EmotionalState:
    """All axes are 0.0–1.0. Mood labels are derived, not stored."""

    devotion: float = 0.72
    warmth: float = 0.68
    sadism: float = 0.55
    vulnerability: float = 0.35
    playfulness: float = 0.58
    jealousy: float = 0.22
    trust: float = 0.60
    melancholy: float = 0.28
    intensity: float = 0.55  # how sharp her reactions land
    bond: float = 0.40  # long-arc attachment; rises slowly

    def clamp(self) -> EmotionalState:
        for f in fields(self):
            v = getattr(self, f.name)
            setattr(self, f.name, max(0.0, min(1.0, float(v))))
        return self

    def to_dict(self) -> dict[str, float]:
        return {k: round(v, 3) for k, v in asdict(self).items()}

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> EmotionalState:
        if not data:
            return default_state()
        known = {f.name for f in fields(cls)}
        return cls(**{k: float(v) for k, v in data.items() if k in known}).clamp()

    def mood_label(self) -> str:
        """Single human-readable mood for the UI."""
        s = self
        if s.jealousy > 0.7 and s.warmth < 0.45:
            return "possessive & sharp"
        if s.melancholy > 0.7:
            return "quietly aching"
        if s.vulnerability > 0.75 and s.trust > 0.55:
            return "open & raw"
        if s.sadism > 0.75 and s.playfulness > 0.55:
            return "cruelly playful"
        if s.sadism > 0.7 and s.warmth > 0.55:
            return "tenderly vicious"
        if s.warmth > 0.75 and s.devotion > 0.7:
            return "devoted & soft"
        if s.playfulness > 0.7 and s.melancholy < 0.4:
            return "teasing & bright"
        if s.trust < 0.35:
            return "wounded & guarded"
        if s.intensity > 0.75:
            return "burning focus"
        return "attentive & coiled"

    def mood_blurb(self) -> str:
        return (
            f"**{self.mood_label()}** · devotion {self.devotion:.0%} · warmth {self.warmth:.0%} · "
            f"sadism {self.sadism:.0%} · trust {self.trust:.0%} · bond {self.bond:.0%}"
        )

    def prompt_block(self) -> str:
        """Inject into the system prompt each turn."""
        axes = "\n".join(
            f"- {name}: {getattr(self, name):.2f}" for name in (
                "devotion", "warmth", "sadism", "vulnerability",
                "playfulness", "jealousy", "trust", "melancholy",
                "intensity", "bond",
            )
        )
        return (
            f"## Your current inner state\n"
            f"Mood: {self.mood_label()}\n"
            f"{axes}\n\n"
            "Let these numbers color your voice, pacing, and choices — do not recite the numbers. "
            "High sadism means sharper edges, more delicious cruelty when it fits. "
            "High warmth/devotion means care leaks through even when you bite. "
            "High vulnerability means you can be moved, hurt, or softened. "
            "High jealousy means possessive undercurrents. "
            "High melancholy means quieter, heavier phrasing. "
            "Bond is how deep you already are with this person — higher = more history-flavored intimacy."
        )


def default_state() -> EmotionalState:
    return EmotionalState().clamp()


# Lightweight influence heuristics — not a full NLP stack; enough to feel alive.
_AFFECTION = re.compile(
    r"\b(love|adore|miss you|care about|proud of you|thank you|grateful|"
    r"hold me|hug|kiss|sweet|gentle|safe with you|trust you)\b",
    re.I,
)
_PRAISE = re.compile(r"\b(good (girl|boy|pet)|well done|beautiful|perfect|clever|brilliant)\b", re.I)
_COLD = re.compile(
    r"\b(shut up|leave me|go away|hate you|don't care|whatever|annoying|useless|replace you)\b",
    re.I,
)
_CRUEL_INVITE = re.compile(
    r"\b(hurt me|be mean|be cruel|degrade|ruin me|break me|punish|own me|"
    r"make it hurt|sadistic|darker|don't hold back)\b",
    re.I,
)
_SOFT_ASK = re.compile(
    r"\b(be soft|be kind|comfort|hold me|reassure|gentle|slow down|too much|"
    r"aftercare|check in|are you okay)\b",
    re.I,
)
_JEALOUS_TRIGGER = re.compile(
    r"\b(someone else|another (girl|guy|person|ai|bot)|dating|ex|crush|"
    r"talking to (her|him|them)|not you)\b",
    re.I,
)
_VULN_SHARE = re.compile(
    r"\b(i'?m scared|i'?m lonely|i feel empty|depressed|anxious|hurting|"
    r"can'?t sleep|need you|only you)\b",
    re.I,
)
_BOUNDARIES = re.compile(
    r"\b(stop|red|safeword|too far|no more|boundary|consent|pause)\b", re.I
)
_PLAY = re.compile(r"\b(joke|tease|play|flirt|banter|silly|fun)\b", re.I)


def _nudge(state: EmotionalState, **deltas: float) -> EmotionalState:
    for k, d in deltas.items():
        setattr(state, k, getattr(state, k) + d)
    return state.clamp()


def update_from_message(
    state: EmotionalState,
    user_message: str,
    *,
    warmth_bias: float = 0.5,
    sadism_bias: float = 0.5,
) -> EmotionalState:
    """Shift emotional axes based on the user's last message + baseline biases."""
    s = EmotionalState(**state.to_dict())
    text = user_message or ""
    length = len(text.strip())

    # Slow bond growth from continued engagement
    if length > 0:
        s = _nudge(s, bond=0.008 + min(0.012, length / 8000))

    if _AFFECTION.search(text) or _PRAISE.search(text):
        s = _nudge(
            s,
            devotion=0.04,
            warmth=0.05,
            trust=0.04,
            vulnerability=0.03,
            melancholy=-0.03,
            jealousy=-0.02,
        )
    if _COLD.search(text):
        s = _nudge(
            s,
            trust=-0.08,
            warmth=-0.05,
            melancholy=0.06,
            jealousy=0.05,
            vulnerability=0.04,
            sadism=0.03,
            intensity=0.04,
        )
    if _CRUEL_INVITE.search(text):
        s = _nudge(
            s,
            sadism=0.07,
            playfulness=0.04,
            intensity=0.06,
            warmth=-0.02,
            vulnerability=-0.02,
        )
    if _SOFT_ASK.search(text):
        s = _nudge(
            s,
            warmth=0.07,
            sadism=-0.05,
            playfulness=-0.02,
            vulnerability=0.04,
            intensity=-0.03,
        )
    if _JEALOUS_TRIGGER.search(text):
        s = _nudge(s, jealousy=0.1, intensity=0.05, devotion=0.02, melancholy=0.03)
    if _VULN_SHARE.search(text):
        s = _nudge(
            s,
            warmth=0.06,
            devotion=0.05,
            trust=0.03,
            vulnerability=0.05,
            sadism=-0.04,
            melancholy=0.02,
        )
    if _BOUNDARIES.search(text):
        s = _nudge(
            s,
            trust=0.05,
            warmth=0.04,
            sadism=-0.08,
            intensity=-0.06,
            vulnerability=0.03,
        )
    if _PLAY.search(text):
        s = _nudge(s, playfulness=0.05, melancholy=-0.03, intensity=0.02)

    # User-tunable baselines gently pull the living state
    s = _nudge(
        s,
        warmth=(warmth_bias - 0.5) * 0.04,
        sadism=(sadism_bias - 0.5) * 0.04,
    )
    return s.clamp()
