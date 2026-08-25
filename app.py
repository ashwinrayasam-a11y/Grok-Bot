"""Grok companions — shared living emotional range, many personalities."""

from __future__ import annotations

import json
import os

import gradio as gr

from companion.companions import (
    DEFAULT_COMPANION_ID,
    get_companion,
    load_session,
    picker_choices,
    stash_session,
)
from companion.emotion import EmotionalState, default_state, update_from_message
from companion.llm import (
    HF_MODELS,
    XAI_MODELS,
    available_backends,
    history_to_messages,
    stream_chat,
)
from companion.personality import COMPANION_NAME, build_system_prompt

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;0,600;1,500&family=Outfit:wght@300;400;500;600&display=swap');

:root {
  --vesper-bg: #140f0c;
  --vesper-panel: #1c1510;
  --vesper-ink: #f3e6d8;
  --vesper-mute: #b9a090;
  --vesper-ember: #c45c26;
  --vesper-rose: #a84d4d;
  --vesper-line: rgba(243, 230, 216, 0.12);
}

.gradio-container {
  font-family: 'Outfit', sans-serif !important;
  background:
    radial-gradient(1200px 600px at 10% -10%, rgba(196, 92, 38, 0.22), transparent 55%),
    radial-gradient(900px 500px at 100% 0%, rgba(168, 77, 77, 0.16), transparent 50%),
    linear-gradient(180deg, #1a120e 0%, #0e0b09 100%) !important;
  color: var(--vesper-ink) !important;
}

#vesper-hero h1 {
  font-family: 'Cormorant Garamond', serif !important;
  font-size: clamp(2.4rem, 5vw, 3.6rem) !important;
  font-weight: 600 !important;
  letter-spacing: 0.02em;
  color: var(--vesper-ink) !important;
  margin: 0 0 0.25rem 0 !important;
}

#vesper-hero p {
  color: var(--vesper-mute) !important;
  font-weight: 300;
  max-width: 42rem;
  line-height: 1.55;
}

#mood-panel {
  border: 1px solid var(--vesper-line) !important;
  background: rgba(28, 21, 16, 0.85) !important;
  border-radius: 4px !important;
  padding: 0.75rem 1rem !important;
}

#companion-picker label {
  color: var(--vesper-mute) !important;
}

footer { display: none !important; }
"""


def _display_name(companion_id: str, custom_name: str = "") -> str:
    return get_companion(companion_id).display_name(custom_name)


def _hero_md(companion_id: str, custom_name: str = "") -> str:
    companion = get_companion(companion_id)
    name = companion.display_name(custom_name)
    return (
        f"# {name}\n"
        f"{companion.tagline}\n\n"
        "Every companion shares the same living emotional range — devotion, warmth, "
        "sadism, trust, bond, and more — starting from a different baseline and "
        "answering in character."
    )


def _mood_md(state: EmotionalState, companion_id: str = DEFAULT_COMPANION_ID, custom_name: str = "") -> str:
    name = _display_name(companion_id, custom_name)
    bars = []
    for axis, val in [
        ("devotion", state.devotion),
        ("warmth", state.warmth),
        ("sadism", state.sadism),
        ("trust", state.trust),
        ("jealousy", state.jealousy),
        ("vulnerability", state.vulnerability),
        ("playfulness", state.playfulness),
        ("melancholy", state.melancholy),
        ("bond", state.bond),
    ]:
        filled = int(round(val * 10))
        bars.append(f"`{axis:12}` {'█' * filled}{'░' * (10 - filled)} {val:.0%}")
    return f"### {name} — {state.mood_label()}\n\n" + "\n".join(bars)


def _models_for_backend(backend: str) -> gr.Dropdown:
    if "xai" in backend.lower() or "grok" in backend.lower():
        choices = XAI_MODELS
        value = XAI_MODELS[0]
    elif "openai" in backend.lower():
        choices = ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]
        value = "gpt-4o-mini"
    else:
        choices = HF_MODELS
        value = HF_MODELS[0]
    return gr.Dropdown(choices=choices, value=value)


def _opening_update(companion_id: str):
    companion = get_companion(companion_id)
    return gr.update(choices=list(companion.openings), value=None)


def respond(
    message: str,
    history: list,
    state_dict: dict,
    user_name: str,
    notes: str,
    warmth_bias: float,
    sadism_bias: float,
    intensity_bias: float,
    backend: str,
    model: str,
    temperature: float,
    hf_token: str,
    api_key: str,
    base_url: str,
    companion_id: str,
    custom_name: str,
    custom_persona: str,
):
    companion = get_companion(companion_id)
    name = companion.display_name(custom_name)
    if not (message or "").strip():
        yield history, state_dict, _mood_md(EmotionalState.from_dict(state_dict), companion_id, custom_name)
        return

    state = EmotionalState.from_dict(state_dict)
    state.intensity = max(0.0, min(1.0, 0.7 * state.intensity + 0.3 * intensity_bias))
    state = update_from_message(
        state, message, warmth_bias=warmth_bias, sadism_bias=sadism_bias
    )

    system = build_system_prompt(
        state.prompt_block(),
        user_name=user_name or "",
        extra_notes=notes or "",
        companion_id=companion.id,
        custom_name=custom_name or "",
        custom_persona=custom_persona or "",
    )
    if intensity_bias > 0.7:
        system += "\n\nBias this reply toward higher emotional intensity and sharper presence."
    elif intensity_bias < 0.35:
        system += "\n\nBias this reply toward quieter, lower-intensity presence."

    messages = history_to_messages(history, system, message)

    new_history = list(history or [])
    new_history.append({"role": "user", "content": message})
    new_history.append({"role": "assistant", "content": ""})

    accumulated = ""
    try:
        for chunk in stream_chat(
            backend=backend,
            model=model,
            messages=messages,
            temperature=temperature,
            hf_token=hf_token or None,
            api_key=api_key or None,
            base_url=base_url or None,
        ):
            accumulated += chunk
            new_history[-1] = {"role": "assistant", "content": accumulated}
            yield new_history, state.to_dict(), _mood_md(state, companion_id, custom_name)
    except Exception as e:
        err = f"*{name} goes quiet for a moment.*\n\n`{type(e).__name__}: {e}`"
        new_history[-1] = {"role": "assistant", "content": err}
        yield new_history, state.to_dict(), _mood_md(state, companion_id, custom_name)
        return

    yield new_history, state.to_dict(), _mood_md(state, companion_id, custom_name)


def switch_companion(
    new_id: str,
    old_id: str,
    sessions: dict,
    state_dict: dict,
    history: list,
    warmth_bias: float,
    sadism_bias: float,
    intensity_bias: float,
    custom_name: str,
):
    new_id = new_id or DEFAULT_COMPANION_ID
    old_id = old_id or DEFAULT_COMPANION_ID
    companion = get_companion(new_id)
    if new_id == old_id:
        return (
            sessions or {},
            new_id,
            state_dict,
            _mood_md(EmotionalState.from_dict(state_dict), new_id, custom_name),
            history or [],
            warmth_bias,
            sadism_bias,
            intensity_bias,
            _hero_md(new_id, custom_name),
            gr.update(placeholder=companion.placeholder),
            _opening_update(new_id),
            gr.update(visible=companion.customizable),
            gr.update(label=companion.call_you_label),
        )
    sessions = stash_session(
        sessions,
        old_id,
        state=state_dict,
        history=history,
        warmth_bias=warmth_bias,
        sadism_bias=sadism_bias,
        intensity_bias=intensity_bias,
    )
    companion = get_companion(new_id)
    saved = load_session(sessions, new_id)
    if saved:
        state = EmotionalState.from_dict(saved.get("state")).to_dict()
        history = saved.get("history") or []
        warmth_bias = float(saved.get("warmth_bias", companion.warmth_bias))
        sadism_bias = float(saved.get("sadism_bias", companion.sadism_bias))
        intensity_bias = float(saved.get("intensity_bias", companion.intensity_bias))
    else:
        state = companion.initial_state().to_dict()
        history = []
        warmth_bias = companion.warmth_bias
        sadism_bias = companion.sadism_bias
        intensity_bias = companion.intensity_bias

    return (
        sessions,
        new_id,
        state,
        _mood_md(EmotionalState.from_dict(state), new_id, custom_name),
        history,
        warmth_bias,
        sadism_bias,
        intensity_bias,
        _hero_md(new_id, custom_name),
        gr.update(placeholder=companion.placeholder),
        _opening_update(new_id),
        gr.update(visible=companion.customizable),
        gr.update(label=companion.call_you_label),
    )


def refresh_custom_labels(custom_name: str, companion_id: str, state_dict: dict):
    return _hero_md(companion_id, custom_name), _mood_md(
        EmotionalState.from_dict(state_dict), companion_id, custom_name
    )


def reset_state(companion_id: str, custom_name: str):
    companion = get_companion(companion_id)
    state = companion.initial_state()
    return (
        state.to_dict(),
        _mood_md(state, companion_id, custom_name),
        [],
        companion.warmth_bias,
        companion.sadism_bias,
        companion.intensity_bias,
    )


def export_state(
    companion_id,
    state_dict,
    history,
    sessions,
    custom_name,
    custom_persona,
    warmth_bias,
    sadism_bias,
    intensity_bias,
):
    packed = stash_session(
        sessions,
        companion_id,
        state=state_dict,
        history=history,
        warmth_bias=warmth_bias,
        sadism_bias=sadism_bias,
        intensity_bias=intensity_bias,
    )
    payload = {
        "companion_id": companion_id,
        "emotional_state": state_dict,
        "history": history,
        "sessions": packed,
        "custom": {"name": custom_name or "", "persona": custom_persona or ""},
    }
    path = "/tmp/companion_save.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    return path


def import_state(file_obj):
    if file_obj is None:
        companion = get_companion(DEFAULT_COMPANION_ID)
        state = companion.initial_state()
        return (
            {},
            companion.id,
            state.to_dict(),
            _mood_md(state, companion.id),
            [],
            companion.warmth_bias,
            companion.sadism_bias,
            companion.intensity_bias,
            _hero_md(companion.id),
            gr.update(value=companion.id),
            gr.update(placeholder=companion.placeholder),
            _opening_update(companion.id),
            gr.update(visible=False),
            "",
            "",
            "No file loaded.",
        )
    path = file_obj if isinstance(file_obj, str) else getattr(file_obj, "name", None)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    companion_id = data.get("companion_id") or DEFAULT_COMPANION_ID
    companion = get_companion(companion_id)
    custom = data.get("custom") or {}
    custom_name = custom.get("name") or ""
    custom_persona = custom.get("persona") or ""
    sessions = data.get("sessions") or {}
    saved = load_session(sessions, companion_id)
    if saved and saved.get("state"):
        state = EmotionalState.from_dict(saved.get("state"))
        history = saved.get("history") or []
        warmth = float(saved.get("warmth_bias", companion.warmth_bias))
        sadism = float(saved.get("sadism_bias", companion.sadism_bias))
        intensity = float(saved.get("intensity_bias", companion.intensity_bias))
    else:
        state = EmotionalState.from_dict(data.get("emotional_state"))
        history = data.get("history") or []
        warmth, sadism, intensity = companion.warmth_bias, companion.sadism_bias, companion.intensity_bias
    return (
        sessions,
        companion.id,
        state.to_dict(),
        _mood_md(state, companion.id, custom_name),
        history,
        warmth,
        sadism,
        intensity,
        _hero_md(companion.id, custom_name),
        gr.update(value=companion.id),
        gr.update(placeholder=companion.placeholder),
        _opening_update(companion.id),
        gr.update(visible=companion.customizable),
        custom_name,
        custom_persona,
        f"Restored {companion.display_name(custom_name)}.",
    )


INITIAL = get_companion(DEFAULT_COMPANION_ID)
INITIAL_STATE = INITIAL.initial_state()

with gr.Blocks(title="Companions — living emotional range") as demo:
    state = gr.State(INITIAL_STATE.to_dict())
    sessions = gr.State({})
    active_id = gr.State(DEFAULT_COMPANION_ID)

    with gr.Row(elem_id="vesper-hero"):
        hero = gr.Markdown(_hero_md(DEFAULT_COMPANION_ID))

    picker = gr.Radio(
        choices=picker_choices(),
        value=DEFAULT_COMPANION_ID,
        label="Companion",
        elem_id="companion-picker",
    )

    with gr.Group(visible=False) as custom_box:
        custom_name = gr.Textbox(label="Companion name", placeholder="e.g. Ash")
        custom_persona = gr.Textbox(
            label="Who they are",
            placeholder="Write the personality. The living emotional range is applied automatically.",
            lines=4,
        )

    with gr.Row():
        with gr.Column(scale=3):
            chatbot = gr.Chatbot(
                height=520,
                show_label=False,
                placeholder=f"Say something. {COMPANION_NAME} is already listening.",
            )
            with gr.Row():
                msg = gr.Textbox(
                    placeholder=INITIAL.placeholder,
                    show_label=False,
                    scale=5,
                    lines=2,
                )
                send = gr.Button("Send", variant="primary", scale=1)

            openings = gr.Dropdown(
                choices=list(INITIAL.openings),
                label="Openings",
                value=None,
            )

        with gr.Column(scale=2):
            mood = gr.Markdown(_mood_md(INITIAL_STATE, DEFAULT_COMPANION_ID), elem_id="mood-panel")
            with gr.Accordion("Presence", open=True):
                warmth_bias = gr.Slider(0, 1, value=INITIAL.warmth_bias, step=0.01, label="Warmth bias")
                sadism_bias = gr.Slider(0, 1, value=INITIAL.sadism_bias, step=0.01, label="Sadism bias")
                intensity_bias = gr.Slider(0, 1, value=INITIAL.intensity_bias, step=0.01, label="Intensity")
                user_name = gr.Textbox(label=INITIAL.call_you_label, placeholder="optional")
                notes = gr.Textbox(
                    label="Private notes / dynamics",
                    placeholder="e.g. soft aftercare after sharp scenes; hates being ignored",
                    lines=3,
                )
            with gr.Accordion("Model & keys", open=False):
                backend = gr.Dropdown(
                    choices=available_backends(),
                    value=available_backends()[0],
                    label="Backend",
                )
                model = gr.Dropdown(choices=HF_MODELS, value=HF_MODELS[0], label="Model")
                temperature = gr.Slider(0.2, 1.3, value=0.92, step=0.01, label="Temperature")
                hf_token = gr.Textbox(
                    label="HF token (optional if HF_TOKEN is set)",
                    type="password",
                    value=os.environ.get("HF_TOKEN", ""),
                )
                api_key = gr.Textbox(
                    label="xAI / OpenAI API key",
                    type="password",
                    value=os.environ.get("XAI_API_KEY") or os.environ.get("OPENAI_API_KEY", ""),
                )
                base_url = gr.Textbox(
                    label="Custom base URL (OpenAI-compatible)",
                    placeholder="https://api.x.ai/v1",
                    value=os.environ.get("OPENAI_BASE_URL", ""),
                )
            with gr.Row():
                reset_btn = gr.Button("Reset mood & chat")
                save_btn = gr.Button("Export")
                load_file = gr.File(label="Import save", file_types=[".json"])
            save_file = gr.File(label="Download", interactive=False)
            status = gr.Markdown("")

    backend.change(fn=_models_for_backend, inputs=backend, outputs=model)
    openings.change(lambda text: text or "", inputs=openings, outputs=msg)
    custom_name.change(
        refresh_custom_labels,
        inputs=[custom_name, picker, state],
        outputs=[hero, mood],
    )

    picker.change(
        switch_companion,
        inputs=[
            picker,
            active_id,
            sessions,
            state,
            chatbot,
            warmth_bias,
            sadism_bias,
            intensity_bias,
            custom_name,
        ],
        outputs=[
            sessions,
            active_id,
            state,
            mood,
            chatbot,
            warmth_bias,
            sadism_bias,
            intensity_bias,
            hero,
            msg,
            openings,
            custom_box,
            user_name,
        ],
    )

    inputs = [
        msg,
        chatbot,
        state,
        user_name,
        notes,
        warmth_bias,
        sadism_bias,
        intensity_bias,
        backend,
        model,
        temperature,
        hf_token,
        api_key,
        base_url,
        picker,
        custom_name,
        custom_persona,
    ]
    outputs = [chatbot, state, mood]

    def _clear_box():
        return ""

    send.click(respond, inputs=inputs, outputs=outputs).then(_clear_box, outputs=msg)
    msg.submit(respond, inputs=inputs, outputs=outputs).then(_clear_box, outputs=msg)

    reset_btn.click(
        reset_state,
        inputs=[picker, custom_name],
        outputs=[state, mood, chatbot, warmth_bias, sadism_bias, intensity_bias],
    )
    save_btn.click(
        export_state,
        inputs=[
            picker,
            state,
            chatbot,
            sessions,
            custom_name,
            custom_persona,
            warmth_bias,
            sadism_bias,
            intensity_bias,
        ],
        outputs=save_file,
    )
    load_file.change(
        import_state,
        inputs=load_file,
        outputs=[
            sessions,
            active_id,
            state,
            mood,
            chatbot,
            warmth_bias,
            sadism_bias,
            intensity_bias,
            hero,
            picker,
            msg,
            openings,
            custom_box,
            custom_name,
            custom_persona,
            status,
        ],
    )

if __name__ == "__main__":
    demo.queue(default_concurrency_limit=4).launch(
        theme=gr.themes.Base(),
        css=CSS,
    )
