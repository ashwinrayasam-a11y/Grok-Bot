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
short_description: Grok companions with a shared living emotional range
tags:
  - chatbot
  - companion
  - roleplay
---

# Companions

The Grok app now has a **companion roster**. Every companion uses the same living emotional range (devotion, warmth, sadism, trust, bond, and more) — they start from different baselines and interpret those feelings in character.

- **Vesper** — loyal, warm, sadistic
- **Maren** — soft care, aftercare, quiet presence
- **Quill** — intellect, curiosity, dry humor
- **Puck** — flirtation, banter, mischief
- **Custom** — write who they are; the emotional range still applies

How you treat the active companion shifts their own emotional state. Switching companions keeps each chat and mood isolated.

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

- **Companion** — pick who you're with; each keeps a separate chat and living mood
- **Warmth / Sadism / Intensity** — soft biases that tug that companion's baseline without freezing the living state
- **What they call you** + **Private notes** — relationship texture injected into the system prompt
- **Export / Import** — save chats + emotional state for every companion as JSON


