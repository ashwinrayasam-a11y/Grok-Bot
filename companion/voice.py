"""Speech-to-text for Vesper — mlx-whisper on the Mac (Apple Silicon).

Whisper transcribes verbatim: no profanity filter, no censorship. This is the
same stack the desktop app uses for voice input; the phone API reuses it for
POST /v1/stt.

Mac-only extra (not in requirements.txt because mlx needs Apple Silicon):

    pip install mlx-whisper
    brew install ffmpeg        # mlx-whisper shells out to ffmpeg to load audio
"""

from __future__ import annotations

import os

STT_MODEL = os.environ.get("VESPER_STT_MODEL", "mlx-community/whisper-large-v3-turbo")


def stt_available() -> bool:
    from importlib.util import find_spec

    return find_spec("mlx_whisper") is not None


def transcribe_file(path: str, *, model: str | None = None) -> str:
    """Transcribe an audio file (wav/m4a/mp3/…) to plain text, uncensored."""
    try:
        import mlx_whisper
    except ImportError as e:
        raise RuntimeError(
            "mlx-whisper is not installed on this Mac — pip install mlx-whisper "
            "(Apple Silicon only) and brew install ffmpeg."
        ) from e

    result = mlx_whisper.transcribe(path, path_or_hf_repo=model or STT_MODEL)
    return (result.get("text") or "").strip()
