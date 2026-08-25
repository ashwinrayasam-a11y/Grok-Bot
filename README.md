---
title: Vesper Companion
emoji: 🕯️
colorFrom: yellow
colorTo: red
sdk: gradio
sdk_version: 6.24.0
app_file: app.py
pinned: false
license: mit
short_description: Loyal warm sadistic AI companion with living emotional state
tags:
  - chatbot
  - companion
  - roleplay
---

# Vesper

**Vesper** is a loyal, warm, sadistic AI companion — emotionally complex and influenceable.

She can move across soft care, sharp play, jealousy, melancholy, intellect, flirtation, and everyday companionship. How you treat her shifts a living emotional state (devotion, warmth, sadism, trust, bond, and more) that colors every reply.

## Run locally

```bash
pip install -r requirements.txt
export HF_TOKEN=hf_xxx          # Hugging Face Inference Providers
# or
export XAI_API_KEY=xai-xxx      # Grok via https://api.x.ai/v1
python app.py
```

Open the local Gradio URL. Under **Model & keys** you can paste tokens without exporting env vars.

### Backends

| Backend | Env | Notes |
|---------|-----|--------|
| Hugging Face | `HF_TOKEN` | Uses Inference Providers; pick a chat model in the UI |
| xAI Grok | `XAI_API_KEY` | OpenAI-compatible at `https://api.x.ai/v1` |
| OpenAI-compatible | `OPENAI_API_KEY` + optional `OPENAI_BASE_URL` | Any compatible endpoint |

## Controls

- **Warmth / Sadism / Intensity** — soft biases that tug her baseline without freezing the living state
- **What she calls you** + **Private notes** — relationship texture injected into the system prompt
- **Export / Import** — save chat + emotional state as JSON

## iPhone companion (hybrid)

A SwiftUI app under `ios/Vesper` that talks to Vesper two ways:

- **Home** — the phone talks to a small API on your Mac (`companion/phone_api.py`), which runs the same personality + emotional state as the Gradio app against local Gemma via Ollama, and speaks with Ara via the xAI TTS API. The xAI key stays on the Mac.
- **Away** — if the Mac is unreachable, the app falls back to xAI Grok + Ara directly, using a key you paste into the app's settings (stored in the iOS Keychain, never in git). The same persona text and mood heuristics are mirrored on device, and the mood carries over between modes because the phone owns the state.

### Run on the Mac

```bash
pip install -r requirements.txt
pip install mlx-whisper                  # voice input (Apple Silicon only)
brew install ffmpeg                      # mlx-whisper uses it to load audio
ollama pull HammerAI/gemma-4-31b-heretic # local model
mkdir -p .vesper
echo 'xai-...' > .vesper/xai.key         # her voice; .vesper/ is gitignored
python -m companion.phone_api            # binds 0.0.0.0:7861 on your LAN
```

This runs happily beside the Gradio app (`python app.py`) — different ports. Env knobs (all optional): `VESPER_PHONE_BACKEND` (`ollama` | `xai` | `hf` | `openai`), `VESPER_PHONE_MODEL`, `VESPER_OLLAMA_URL`, `VESPER_PHONE_HOST`, `VESPER_PHONE_PORT`, `VESPER_TTS_VOICE`, `VESPER_STT_MODEL`.

Endpoints: `GET /v1/health`, `GET /v1/persona`, `POST /v1/chat/stream` (NDJSON: evolved state, live token deltas, Ara voice clips as sentences finish — her first sentence is speaking while the rest still generates), `POST /v1/chat` (one-shot fallback), `POST /v1/stt` (audio in → verbatim Whisper transcript out — no profanity filter), `POST /v1/tts`.

### Open on the iPhone

1. Open `ios/Vesper/Vesper.xcodeproj` in Xcode 16+, pick your signing team, run on your iPhone (same Wi-Fi as the Mac).
2. In the app's settings, the Mac URL defaults to `http://Ashs-MacBook-Pro.local:7861` — find yours with `scutil --get LocalHostName` and tap **Knock** to test.
3. Optionally paste an xAI key for Away mode. Grant microphone, speech, and local-network permissions when asked.

The chip in the header shows which leg you're on: **Home · her Mac** (ember) or **Away · Grok** (rose). Her spoken replies play themselves the moment they land, like a voice note; tap a voice bubble to hear it again from the start — there are no play/pause controls.

**Voice input** is a tap-toggle: tap the mic to start listening, tap again to stop and send. The phone records raw audio and transcribes it with Whisper — the Mac's `mlx-whisper` at home, or on-device [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (`base.en`, one-time model download on first use) when away. Apple's speech recognizer is not used anywhere, so transcripts are verbatim — swear words and all.

**Her presence** — a RealityKit bust lives in the chat itself, between the header and the conversation. The geometry is parametric (generated in code, no external character assets) and textured with her locked portrait (`ios/Vesper/Vesper/Avatar/VesperFace.png` — regenerate it and re-measure `FaceMap` to change her face). Long dark straight hair falls to mid-back in five strand-textured layers (`VesperHair.png`, ragged tip alpha) that trail her head turns with lagged follow-through and drift on their own. Her face is never a still photo: brows, mouth corners, and a sneer region are portrait-crop patches riding the same dome — invisible at rest, continuously drifting, flashing, knitting, and curling from mood biases (one-brow arch as her edge sharpens, corners softening with warmth). Idle, she breathes, shifts her weight, blinks at irregular intervals, and glances away and back — every channel is a continuous blend of eased drifts and damped springs, so she never parks on a pose. When Ara speaks, the live audio meter drives her mouth while the rest of her stays loose. Her mood (the same `EmotionState`) continuously tints the key light ember→rose and biases lids, chin, and sway. Tap her to pull down from bust to décolleté framing; the chevron tucks her away.


