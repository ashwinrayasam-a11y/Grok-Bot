"""Vesper — emotionally complex AI companion."""

from .emotion import EmotionalState, default_state, update_from_message
from .personality import build_system_prompt, COMPANION_NAME

__all__ = [
    "EmotionalState",
    "default_state",
    "update_from_message",
    "build_system_prompt",
    "COMPANION_NAME",
]
