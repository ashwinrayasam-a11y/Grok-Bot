"""Emotionally complex AI companions with a shared living emotional range."""

from .companions import (
    COMPANIONS,
    DEFAULT_COMPANION_ID,
    EMOTIONAL_RANGE,
    Companion,
    build_system_prompt,
    get_companion,
    list_companions,
)
from .emotion import EmotionalState, default_state, update_from_message
from .personality import BASE_PERSONA, COMPANION_NAME

__all__ = [
    "BASE_PERSONA",
    "COMPANION_NAME",
    "COMPANIONS",
    "DEFAULT_COMPANION_ID",
    "EMOTIONAL_RANGE",
    "Companion",
    "EmotionalState",
    "build_system_prompt",
    "default_state",
    "get_companion",
    "list_companions",
    "update_from_message",
]
