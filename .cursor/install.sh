#!/usr/bin/env bash
# Idempotent Cloud Agent setup for Vesper.
#
# Prepares everything needed to run the two Python services end to end without
# any external API keys:
#   - Python dependencies (app + test tooling)
#   - Ollama, a local OpenAI-compatible LLM server (the phone API's default
#     backend; here it also powers the Gradio app)
#   - the gemma3:1b model, plus name aliases so the stock Gradio model dropdown
#     and the phone API resolve to the local model with no keys.
#
# The iOS SwiftUI app under ios/ builds on macOS with Xcode and is out of scope
# for this Linux environment.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODEL="gemma3:1b"
export OLLAMA_HOST="127.0.0.1:11434"

echo "==> Installing Python dependencies"
pip install --user --no-warn-script-location -r requirements.txt pytest

echo "==> Ensuring zstd (needed by the Ollama installer)"
if ! command -v zstd >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq zstd
fi

echo "==> Ensuring Ollama"
if ! command -v ollama >/dev/null 2>&1; then
  curl -fsSL https://ollama.com/install.sh | sh
fi

echo "==> Ensuring local model + aliases ($MODEL)"
if ! ollama list 2>/dev/null | grep -q "^${MODEL}"; then
  # Ollama needs a running daemon to pull/copy. Start a throwaway one; the
  # model files land in ~/.ollama and persist. The long-lived daemon for the
  # running agent is started by the "ollama" terminal, not here.
  ollama serve >/tmp/ollama-install.log 2>&1 &
  serve_pid=$!
  for _ in $(seq 1 30); do
    curl -sf "http://${OLLAMA_HOST}/api/version" >/dev/null 2>&1 && break
    sleep 1
  done
  ollama pull "$MODEL"
  # Alias the local model to the exact names the stock UIs request by default,
  # so both apps work with zero API keys and zero dropdown changes.
  ollama cp "$MODEL" "Qwen/Qwen2.5-72B-Instruct" || true
  ollama cp "$MODEL" "gpt-4o-mini" || true
  kill "$serve_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true
fi

echo "==> Setup complete"
