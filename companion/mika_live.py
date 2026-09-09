"""Live Mika bridge — the same path the Mac uses.

Outbound: POST to the Mika App Chat Bridge webhook with
`{turnId, text, replyUrl, warmth, sadism, intensity}`.
Inbound: the bot POSTs `{turnId, reply}` back to `replyUrl`, which is the
Tailscale Funnel URL proxying to a tiny local listener this module runs
(default port 18765 — the same port the Funnel already targets).

Secrets and config are files/env only (all gitignored), shared with the Mac:
    .vesper/mika.webhook.url    or  MIKA_WEBHOOK_URL
    .vesper/mika.webhook.key    or  MIKA_WEBHOOK_KEY
    .vesper/mika.reply.base     or  VESPER_MIKA_REPLY_BASE
searched in ./.vesper, ~/Grok-Bot/.vesper, and ~/.vesper.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import httpx

log = logging.getLogger("vesper.mika")

REPO_ROOT = Path(__file__).resolve().parent.parent

_lock = threading.Lock()
_events: dict[str, threading.Event] = {}
_replies: dict[str, str] = {}
_server: ThreadingHTTPServer | None = None
_server_lock = threading.Lock()


def _read_first(name: str) -> str | None:
    for base in (REPO_ROOT / ".vesper", Path.home() / "Grok-Bot" / ".vesper", Path.home() / ".vesper"):
        path = base / name
        try:
            if path.is_file():
                value = path.read_text(encoding="utf-8").strip()
                if value:
                    return value
        except OSError:
            continue
    return None


def resolve_webhook() -> tuple[str | None, str | None]:
    url = (os.environ.get("MIKA_WEBHOOK_URL") or "").strip() or _read_first("mika.webhook.url")
    key = (os.environ.get("MIKA_WEBHOOK_KEY") or "").strip() or _read_first("mika.webhook.key")
    return url, key


def resolve_reply_base() -> str | None:
    return (os.environ.get("VESPER_MIKA_REPLY_BASE") or "").strip() or _read_first("mika.reply.base")


def deliver(turn_id: str, reply: str) -> bool:
    """A reply arrived (via the funnel listener). Wake the waiting turn."""
    with _lock:
        event = _events.get(turn_id)
        if event is None:
            return False
        _replies[turn_id] = reply
        event.set()
        return True


class _ReplyHandler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 — http.server API
        if self.path.rstrip("/").split("?")[0].endswith("reply"):
            try:
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"{}")
                matched = deliver(str(body.get("turnId", "")), str(body.get("reply", "")))
            except (ValueError, json.JSONDecodeError):
                matched = False
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ok": True, "matched": matched}).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):  # keep the phone API log quiet
        return


def ensure_reply_listener(port: int) -> bool:
    """Bind the funnel-facing reply listener once. False if the port is taken
    (e.g. the Mac app's own live listener is running)."""
    global _server
    with _server_lock:
        if _server is not None:
            return True
        try:
            server = ThreadingHTTPServer(("0.0.0.0", port), _ReplyHandler)
        except OSError:
            return False
        _server = server
        threading.Thread(target=server.serve_forever, daemon=True, name="mika-reply").start()
        log.info("Mika reply listener on :%d", port)
        return True


def live_turn(
    *,
    webhook_url: str,
    webhook_key: str,
    text: str,
    warmth: float,
    sadism: float,
    intensity: float,
    reply_base: str,
    timeout: float = 75.0,
) -> str:
    """One live exchange: webhook out, block until the bot posts back."""
    turn_id = str(uuid.uuid4())
    event = threading.Event()
    with _lock:
        _events[turn_id] = event
    try:
        httpx.post(
            webhook_url,
            json={
                "turnId": turn_id,
                "text": text,
                "replyUrl": reply_base.rstrip("/") + "/reply",
                "warmth": warmth,
                "sadism": sadism,
                "intensity": intensity,
            },
            headers={
                "Authorization": f"Bearer {webhook_key}",
                "X-Automation-Key": webhook_key,
            },
            timeout=15,
        ).raise_for_status()
        if not event.wait(timeout):
            raise TimeoutError("no reply from the Mika bridge in time")
        with _lock:
            return _replies.pop(turn_id, "")
    finally:
        with _lock:
            _events.pop(turn_id, None)
            _replies.pop(turn_id, None)
