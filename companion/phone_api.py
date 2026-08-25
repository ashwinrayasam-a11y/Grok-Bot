"""LAN phone API — the bridge between Vesper's home on the Mac and the iOS app.

Runs beside the Gradio app and reuses the exact same personality, emotional
state, and LLM plumbing from this package. The iPhone owns the conversation
history and emotional state (so mood survives roaming between Home and Away
mode); this service is stateless: each request carries state in, and gets the
evolved state back.

Run it on the Mac:

    python -m companion.phone_api          # binds 0.0.0.0:7861

Backend defaults to local Gemma via Ollama (OpenAI-compatible at
http://127.0.0.1:11434/v1). Her voice is Ara via the xAI TTS API; the key is
read from XAI_API_KEY or .vesper/xai.key and never leaves the Mac.
"""

from __future__ import annotations

import base64
import logging
import os
import re
import tempfile
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel, Field

from .emotion import EmotionalState, update_from_message
from .llm import DEFAULT_HF_MODEL, history_to_messages, stream_chat
from .personality import BASE_PERSONA, COMPANION_NAME, build_system_prompt
from .voice import stt_available, transcribe_file

log = logging.getLogger("vesper.phone")

REPO_ROOT = Path(__file__).resolve().parent.parent

BACKEND = os.environ.get("VESPER_PHONE_BACKEND", "ollama").lower()
OLLAMA_URL = os.environ.get("VESPER_OLLAMA_URL", "http://127.0.0.1:11434/v1")
TTS_URL = os.environ.get("VESPER_TTS_URL", "https://api.x.ai/v1/tts")
TTS_VOICE = os.environ.get("VESPER_TTS_VOICE", "ara")
TTS_LANGUAGE = os.environ.get("VESPER_TTS_LANGUAGE", "en")

_MODEL_DEFAULTS = {
    "ollama": "HammerAI/gemma-4-31b-heretic",
    "xai": "grok-4",
    "hf": DEFAULT_HF_MODEL,
    "openai": "gpt-4o-mini",
}


def _model() -> str:
    return os.environ.get("VESPER_PHONE_MODEL") or _MODEL_DEFAULTS.get(
        BACKEND, _MODEL_DEFAULTS["ollama"]
    )


def _xai_key() -> str | None:
    """xAI key from env, or the gitignored key file — stays on the Mac."""
    for env in ("XAI_API_KEY", "GROK_API_KEY"):
        value = (os.environ.get(env) or "").strip()
        if value:
            return value
    for path in (REPO_ROOT / ".vesper" / "xai.key", Path.home() / ".vesper" / "xai.key"):
        try:
            if path.is_file():
                value = path.read_text(encoding="utf-8").strip()
                if value:
                    return value
        except OSError:
            continue
    return None


def _backend_kwargs() -> dict[str, Any]:
    """Map the configured backend onto stream_chat() arguments."""
    if BACKEND in ("ollama", "local", "gemma"):
        return {
            "backend": "OpenAI-compatible",
            "model": _model(),
            "base_url": OLLAMA_URL,
            # Ollama ignores the key but the OpenAI client requires one.
            "api_key": os.environ.get("OLLAMA_API_KEY", "ollama"),
        }
    if BACKEND in ("xai", "grok"):
        return {"backend": "xAI Grok", "model": _model(), "api_key": _xai_key()}
    if BACKEND in ("hf", "huggingface"):
        return {"backend": "Hugging Face", "model": _model()}
    return {
        "backend": "OpenAI-compatible",
        "model": _model(),
        "base_url": os.environ.get("OPENAI_BASE_URL"),
        "api_key": os.environ.get("OPENAI_API_KEY"),
    }


_MD_NOISE = re.compile(r"[*_`#>]+")


def _speakable(text: str) -> str:
    """Strip markdown marks so Ara doesn't read asterisks aloud."""
    return re.sub(r"\s+", " ", _MD_NOISE.sub(" ", text)).strip()[:4000]


def _synthesize(text: str) -> tuple[bytes, str] | None:
    """Ara says it. Returns (audio bytes, mime) or None when voice is unavailable."""
    key = _xai_key()
    speakable = _speakable(text)
    if not key or not speakable:
        return None
    try:
        response = httpx.post(
            TTS_URL,
            headers={"Authorization": f"Bearer {key}"},
            json={"text": speakable, "voice_id": TTS_VOICE, "language": TTS_LANGUAGE},
            timeout=60,
        )
        response.raise_for_status()
        return response.content, response.headers.get("content-type", "audio/mpeg")
    except httpx.HTTPError as e:
        log.warning("TTS failed, replying without voice: %s", e)
        return None


class ChatTurn(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    message: str
    history: list[ChatTurn] = Field(default_factory=list)
    state: dict[str, float] | None = None
    user_name: str = ""
    notes: str = ""
    warmth_bias: float = 0.55
    sadism_bias: float = 0.55
    intensity: float = 0.55
    want_audio: bool = True
    temperature: float = 0.92


class ChatResponse(BaseModel):
    reply: str
    state: dict[str, float]
    mood: str
    audio_b64: str | None = None
    audio_mime: str | None = None
    backend: str
    model: str


class TTSRequest(BaseModel):
    text: str


app = FastAPI(title=f"{COMPANION_NAME} phone API", version="1.0.0")


@app.get("/v1/health")
def health() -> dict[str, Any]:
    kwargs = _backend_kwargs()
    return {
        "ok": True,
        "name": COMPANION_NAME,
        "mode": "home",
        "backend": kwargs["backend"],
        "model": kwargs["model"],
        "tts": bool(_xai_key()),
        "voice": TTS_VOICE,
        "stt": stt_available(),
    }


@app.get("/v1/persona")
def persona() -> dict[str, str]:
    """The exact persona text, so the phone's Away mode can stay in character."""
    return {"name": COMPANION_NAME, "base_persona": BASE_PERSONA}


@app.post("/v1/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    message = (req.message or "").strip()
    if not message:
        raise HTTPException(status_code=400, detail="message is empty")

    # Same turn pipeline as app.py's respond(): blend intensity, drift the
    # living state from the message, then build the system prompt.
    state = EmotionalState.from_dict(req.state)
    state.intensity = max(0.0, min(1.0, 0.7 * state.intensity + 0.3 * req.intensity))
    state = update_from_message(
        state, message, warmth_bias=req.warmth_bias, sadism_bias=req.sadism_bias
    )

    system = build_system_prompt(
        state.prompt_block(), user_name=req.user_name, extra_notes=req.notes
    )
    if req.intensity > 0.7:
        system += "\n\nBias this reply toward higher emotional intensity and sharper presence."
    elif req.intensity < 0.35:
        system += "\n\nBias this reply toward quieter, lower-intensity presence."

    history = [{"role": t.role, "content": t.content} for t in req.history]
    messages = history_to_messages(history, system, message)

    kwargs = _backend_kwargs()
    try:
        reply = "".join(
            stream_chat(messages=messages, temperature=req.temperature, **kwargs)
        ).strip()
    except Exception as e:  # surfaced to the phone as a quiet-bubble error
        raise HTTPException(status_code=502, detail=f"{type(e).__name__}: {e}")
    if not reply:
        raise HTTPException(status_code=502, detail="empty reply from the model")

    audio_b64: str | None = None
    audio_mime: str | None = None
    if req.want_audio:
        audio = _synthesize(reply)
        if audio:
            audio_b64 = base64.b64encode(audio[0]).decode("ascii")
            audio_mime = audio[1]

    return ChatResponse(
        reply=reply,
        state=state.to_dict(),
        mood=state.mood_label(),
        audio_b64=audio_b64,
        audio_mime=audio_mime,
        backend=kwargs["backend"],
        model=kwargs["model"],
    )


@app.post("/v1/stt")
def stt(audio: UploadFile = File(...)) -> dict[str, str]:
    """Whisper on the Mac — verbatim transcription, no profanity filter."""
    data = audio.file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty audio upload")
    suffix = Path(audio.filename or "clip.wav").suffix or ".wav"
    tmp = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
    try:
        tmp.write(data)
        tmp.close()
        text = transcribe_file(tmp.name)
    except RuntimeError as e:  # mlx-whisper not installed on this Mac
        raise HTTPException(status_code=503, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"{type(e).__name__}: {e}")
    finally:
        os.unlink(tmp.name)
    return {"text": text}


@app.post("/v1/tts")
def tts(req: TTSRequest) -> dict[str, str]:
    audio = _synthesize(req.text)
    if not audio:
        raise HTTPException(
            status_code=503,
            detail="No voice available — put the xAI key in .vesper/xai.key or XAI_API_KEY on the Mac.",
        )
    return {
        "audio_b64": base64.b64encode(audio[0]).decode("ascii"),
        "audio_mime": audio[1],
    }


def main() -> None:
    import uvicorn

    uvicorn.run(
        "companion.phone_api:app",
        host=os.environ.get("VESPER_PHONE_HOST", "0.0.0.0"),
        port=int(os.environ.get("VESPER_PHONE_PORT", "7861")),
    )


if __name__ == "__main__":
    main()
