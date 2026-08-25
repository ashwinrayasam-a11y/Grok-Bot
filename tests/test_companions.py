"""Companion roster + shared emotional range."""

from companion.companions import (
    EMOTIONAL_RANGE,
    VESPER_PERSONA,
    build_system_prompt,
    get_companion,
    list_companions,
    load_session,
    stash_session,
)
from companion.emotion import default_state, update_from_message
from companion.personality import BASE_PERSONA, COMPANION_NAME


def test_vesper_persona_unchanged():
    assert COMPANION_NAME == "Vesper"
    assert BASE_PERSONA == VESPER_PERSONA
    assert "Emotional range you must cover" in BASE_PERSONA
    default = build_system_prompt("STATE")
    assert default.startswith(VESPER_PERSONA)
    assert default.endswith("STATE")


def test_every_companion_includes_emotional_range():
    for companion in list_companions():
        persona = companion.full_persona(custom_name="Ash", custom_persona="A quiet strategist.")
        assert "Emotional range you must cover" in persona
        assert "soft comfort, aftercare, quiet presence" in persona
        assert "everyday companionship" in persona
        assert companion.initial_state().warmth >= 0


def test_custom_companion_applies_range_to_user_persona():
    custom = get_companion("custom")
    persona = custom.full_persona(
        custom_name="Ash",
        custom_persona="A quiet strategist who keeps score.",
    )
    assert "You are **Ash**" in persona
    assert "quiet strategist who keeps score" in persona
    assert EMOTIONAL_RANGE in persona
    assert "Hard limits" in persona


def test_unknown_companion_falls_back_to_vesper():
    assert get_companion("nope").id == "vesper"
    assert get_companion(None).id == "vesper"


def test_companion_baselines_differ():
    vesper = get_companion("vesper").initial_state()
    maren = get_companion("maren").initial_state()
    puck = get_companion("puck").initial_state()
    assert maren.warmth > vesper.warmth
    assert maren.sadism < vesper.sadism
    assert puck.playfulness > vesper.playfulness


def test_default_state_overrides():
    state = default_state(warmth=0.1, sadism=0.9)
    assert state.warmth == 0.1
    assert state.sadism == 0.9
    assert 0 <= state.bond <= 1


def test_session_isolation():
    vesper = get_companion("vesper")
    maren = get_companion("maren")
    vesper_state = update_from_message(vesper.initial_state(), "I love you and I feel safe with you.")
    sessions = stash_session(
        {},
        "vesper",
        state=vesper_state.to_dict(),
        history=[{"role": "user", "content": "hi"}],
        warmth_bias=0.7,
        sadism_bias=0.2,
        intensity_bias=0.4,
    )
    sessions = stash_session(
        sessions,
        "maren",
        state=maren.initial_state().to_dict(),
        history=[],
        warmth_bias=maren.warmth_bias,
        sadism_bias=maren.sadism_bias,
        intensity_bias=maren.intensity_bias,
    )
    restored = load_session(sessions, "vesper")
    assert restored["history"][0]["content"] == "hi"
    assert restored["state"]["warmth"] > vesper.initial_state().warmth
    assert load_session(sessions, "maren")["history"] == []


def test_build_system_prompt_uses_named_companion():
    block = get_companion("quill").initial_state().prompt_block()
    prompt = build_system_prompt(block, companion_id="quill", user_name="Ash")
    assert "You are **Quill**" in prompt
    assert "They go by: **Ash**" in prompt
    assert "Emotional range you must cover" in prompt
    assert "You are **Vesper**" not in prompt


if __name__ == "__main__":
    test_vesper_persona_unchanged()
    test_every_companion_includes_emotional_range()
    test_custom_companion_applies_range_to_user_persona()
    test_unknown_companion_falls_back_to_vesper()
    test_companion_baselines_differ()
    test_default_state_overrides()
    test_session_isolation()
    test_build_system_prompt_uses_named_companion()
    print("ok")
