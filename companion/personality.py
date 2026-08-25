"""Core persona API — Vesper by default, any roster companion on request."""

from .companions import (
    COMPANIONS,
    DEFAULT_COMPANION_ID,
    EMOTIONAL_RANGE,
    VESPER_PERSONA,
    Companion,
    build_system_prompt,
    get_companion,
    list_companions,
)

COMPANION_NAME = "Vesper"
BASE_PERSONA = VESPER_PERSONA

__all__ = [
    "BASE_PERSONA",
    "COMPANION_NAME",
    "COMPANIONS",
    "DEFAULT_COMPANION_ID",
    "EMOTIONAL_RANGE",
    "Companion",
    "build_system_prompt",
    "get_companion",
    "list_companions",
]
