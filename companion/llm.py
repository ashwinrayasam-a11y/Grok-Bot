"""LLM backends: Hugging Face Inference Providers + OpenAI-compatible (Grok/xAI, etc.)."""

from __future__ import annotations

import os
from typing import Any, Iterator

DEFAULT_HF_MODEL = "Qwen/Qwen2.5-72B-Instruct"
DEFAULT_XAI_MODEL = "grok-2-latest"

HF_MODELS = [
    "Qwen/Qwen2.5-72B-Instruct",
    "Qwen/Qwen3-32B",
    "meta-llama/Llama-3.3-70B-Instruct",
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b",
    "deepseek-ai/DeepSeek-V3",
]

XAI_MODELS = [
    "grok-2-latest",
    "grok-3",
    "grok-3-mini",
    "grok-4",
]


def _hf_token(explicit: str | None = None) -> str | None:
    return (explicit or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_HUB_TOKEN") or "").strip() or None


def _xai_key(explicit: str | None = None) -> str | None:
    return (explicit or os.environ.get("XAI_API_KEY") or os.environ.get("GROK_API_KEY") or "").strip() or None


def _openai_key(explicit: str | None = None) -> str | None:
    return (explicit or os.environ.get("OPENAI_API_KEY") or "").strip() or None


def available_backends() -> list[str]:
    backends = []
    if _hf_token():
        backends.append("Hugging Face")
    if _xai_key():
        backends.append("xAI Grok")
    if _openai_key() or os.environ.get("OPENAI_BASE_URL"):
        backends.append("OpenAI-compatible")
    if not backends:
        backends = ["Hugging Face", "xAI Grok", "OpenAI-compatible"]
    return backends


def history_to_messages(
    history: list[dict[str, Any]] | list[list[str]],
    system: str,
    user_message: str,
) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = [{"role": "system", "content": system}]

    # Gradio 6 ChatInterface may pass list of {role, content} or tuples
    for item in history or []:
        if isinstance(item, dict):
            role = item.get("role")
            content = item.get("content", "")
            if role in ("user", "assistant") and content:
                if isinstance(content, list):
                    # multimodal — take text parts
                    text = " ".join(
                        p.get("text", "") if isinstance(p, dict) else str(p) for p in content
                    ).strip()
                    if text:
                        messages.append({"role": role, "content": text})
                else:
                    messages.append({"role": role, "content": str(content)})
        elif isinstance(item, (list, tuple)) and len(item) >= 2:
            u, a = item[0], item[1]
            if u:
                messages.append({"role": "user", "content": str(u)})
            if a:
                messages.append({"role": "assistant", "content": str(a)})

    messages.append({"role": "user", "content": user_message})
    return messages


def stream_chat(
    *,
    backend: str,
    model: str,
    messages: list[dict[str, str]],
    temperature: float = 0.9,
    max_tokens: int = 900,
    hf_token: str | None = None,
    api_key: str | None = None,
    base_url: str | None = None,
) -> Iterator[str]:
    backend_l = (backend or "").lower()

    if "hugging" in backend_l or backend_l == "hf":
        yield from _stream_hf(
            model=model or DEFAULT_HF_MODEL,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            token=hf_token,
        )
        return

    if "xai" in backend_l or "grok" in backend_l:
        yield from _stream_openai_compatible(
            model=model or DEFAULT_XAI_MODEL,
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            api_key=api_key or _xai_key(),
            base_url=base_url or "https://api.x.ai/v1",
        )
        return

    yield from _stream_openai_compatible(
        model=model or "gpt-4o-mini",
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
        api_key=api_key or _openai_key(),
        base_url=base_url or os.environ.get("OPENAI_BASE_URL") or "https://api.openai.com/v1",
    )


def _stream_hf(
    *,
    model: str,
    messages: list[dict[str, str]],
    temperature: float,
    max_tokens: int,
    token: str | None,
) -> Iterator[str]:
    from huggingface_hub import InferenceClient

    tok = _hf_token(token)
    if not tok:
        raise RuntimeError(
            "No Hugging Face token. Set HF_TOKEN, or paste a token in Settings "
            "(https://huggingface.co/settings/tokens — needs inference access)."
        )

    client = InferenceClient(token=tok)
    stream = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
        stream=True,
    )
    for event in stream:
        try:
            delta = event.choices[0].delta.content
        except (AttributeError, IndexError, KeyError):
            delta = None
        if delta:
            yield delta


def _stream_openai_compatible(
    *,
    model: str,
    messages: list[dict[str, str]],
    temperature: float,
    max_tokens: int,
    api_key: str | None,
    base_url: str,
) -> Iterator[str]:
    from openai import OpenAI

    if not api_key:
        raise RuntimeError(
            "No API key for this backend. Set XAI_API_KEY / OPENAI_API_KEY, "
            "or paste a key in Settings."
        )

    client = OpenAI(api_key=api_key, base_url=base_url)
    stream = client.chat.completions.create(
        model=model,
        messages=messages,
        temperature=temperature,
        max_tokens=max_tokens,
        stream=True,
    )
    for event in stream:
        try:
            delta = event.choices[0].delta.content
        except (AttributeError, IndexError):
            delta = None
        if delta:
            yield delta
