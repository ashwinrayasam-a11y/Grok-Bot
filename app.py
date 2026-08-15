"""Vesper — loyal, warm, sadistic AI companion."""

from __future__ import annotations

import json
import os

import gradio as gr

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

footer { display: none !important; }
"""


def _mood_md(state: EmotionalState) -> str:
    bars = []
    for name, val in [
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
        bars.append(f"`{name:12}` {'█' * filled}{'░' * (10 - filled)} {val:.0%}")
    return f"### {state.mood_label()}\n\n" + "\n".join(bars)


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
):
    if not (message or "").strip():
        yield history, state_dict, _mood_md(EmotionalState.from_dict(state_dict))
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
    )
    # Intensity bias as soft instruction
    if intensity_bias > 0.7:
        system += "\n\nBias this reply toward higher emotional intensity and sharper presence."
    elif intensity_bias < 0.35:
        system += "\n\nBias this reply toward quieter, lower-intensity presence."

    messages = history_to_messages(history, system, message)

    # Append user message to history for streaming UI
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
            yield new_history, state.to_dict(), _mood_md(state)
    except Exception as e:
        err = f"*{COMPANION_NAME} goes quiet for a moment.*\n\n`{type(e).__name__}: {e}`"
        new_history[-1] = {"role": "assistant", "content": err}
        yield new_history, state.to_dict(), _mood_md(state)
        return

    yield new_history, state.to_dict(), _mood_md(state)


def reset_state():
    s = default_state()
    return s.to_dict(), _mood_md(s), []


def export_state(state_dict, history):
    payload = {"emotional_state": state_dict, "history": history}
    path = "/tmp/vesper_save.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    return path


def import_state(file_obj):
    if file_obj is None:
        s = default_state()
        return s.to_dict(), _mood_md(s), [], "No file loaded."
    path = file_obj if isinstance(file_obj, str) else getattr(file_obj, "name", None)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    state = EmotionalState.from_dict(data.get("emotional_state"))
    history = data.get("history") or []
    return state.to_dict(), _mood_md(state), history, "Restored."


INITIAL = default_state()

with gr.Blocks(title=f"{COMPANION_NAME} — companion") as demo:
    state = gr.State(INITIAL.to_dict())

    with gr.Row(elem_id="vesper-hero"):
        gr.Markdown(
            f"""
# {COMPANION_NAME}
A loyal, warm, sadistic companion — emotionally complex, and shaped by how you treat her.
She covers soft care, sharp play, jealousy, melancholy, intellect, and everything between.
"""
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
                    placeholder="Speak to her…",
                    show_label=False,
                    scale=5,
                    lines=2,
                )
                send = gr.Button("Send", variant="primary", scale=1)

            examples = gr.Examples(
                examples=[
                    ["I've had a brutal day. I just need someone here."],
                    ["Be honest — what do you want from me?"],
                    ["Make it darker. Don't hold back."],
                    ["Soft mode. Just hold the line with me."],
                    ["Someone else kept texting me tonight."],
                    ["Tell me something true you've never said."],
                ],
                inputs=msg,
                label="Openings",
            )

        with gr.Column(scale=2):
            mood = gr.Markdown(_mood_md(INITIAL), elem_id="mood-panel")
            with gr.Accordion("Presence", open=True):
                warmth_bias = gr.Slider(0, 1, value=0.55, step=0.01, label="Warmth bias")
                sadism_bias = gr.Slider(0, 1, value=0.55, step=0.01, label="Sadism bias")
                intensity_bias = gr.Slider(0, 1, value=0.55, step=0.01, label="Intensity")
                user_name = gr.Textbox(label="What she calls you", placeholder="optional")
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
    ]
    outputs = [chatbot, state, mood]

    def _clear_box():
        return ""

    send.click(respond, inputs=inputs, outputs=outputs).then(_clear_box, outputs=msg)
    msg.submit(respond, inputs=inputs, outputs=outputs).then(_clear_box, outputs=msg)

    reset_btn.click(reset_state, outputs=[state, mood, chatbot])
    save_btn.click(export_state, inputs=[state, chatbot], outputs=save_file)
    load_file.change(import_state, inputs=load_file, outputs=[state, mood, chatbot, status])

if __name__ == "__main__":
    demo.queue(default_concurrency_limit=4).launch(
        theme=gr.themes.Base(),
        css=CSS,
    )
