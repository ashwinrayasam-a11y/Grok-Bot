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


