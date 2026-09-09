"""Phone API checks with the LLM and TTS stubbed out."""

import base64
import json

from fastapi.testclient import TestClient

import companion.phone_api as phone_api
from companion.personality import BASE_PERSONA

client = TestClient(phone_api.app)


def _fake_stream(**kwargs):
    yield "still "
    yield "here."


def test_health_shape():
    r = client.get("/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["ok"] is True
    assert body["name"] == "Vesper"
    assert body["mode"] == "home"


def test_persona_matches_source():
    r = client.get("/v1/persona")
    assert r.status_code == 200
    assert r.json()["base_persona"] == BASE_PERSONA


def test_chat_replies_and_evolves_state(monkeypatch):
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: _fake_stream(**kw))
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)
    r = client.post(
        "/v1/chat", json={"message": "I love you and I feel safe with you."}
    )
    assert r.status_code == 200
    body = r.json()
    assert body["reply"] == "still here."
    # Affection raises warmth above the 0.68 default (same heuristics as the Mac app).
    assert body["state"]["warmth"] > 0.68
    assert body["mood"]
    assert body["audio_b64"] is None


def test_chat_returns_audio_when_available(monkeypatch):
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: _fake_stream(**kw))
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: (b"mp3!", "audio/mpeg"))
    r = client.post("/v1/chat", json={"message": "hey you"})
    assert r.status_code == 200
    body = r.json()
    assert base64.b64decode(body["audio_b64"]) == b"mp3!"
    assert body["audio_mime"] == "audio/mpeg"


def test_chat_carries_history_and_state(monkeypatch):
    captured = {}

    def spy_stream(**kw):
        captured.update(kw)
        yield "mm."

    monkeypatch.setattr(phone_api, "stream_chat", spy_stream)
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)
    r = client.post(
        "/v1/chat",
        json={
            "message": "and now?",
            "history": [
                {"role": "user", "content": "hello"},
                {"role": "assistant", "content": "there you are."},
            ],
            "state": {"warmth": 0.9, "sadism": 0.1},
            "user_name": "Ash",
        },
    )
    assert r.status_code == 200
    roles = [m["role"] for m in captured["messages"]]
    assert roles == ["system", "user", "assistant", "user"]
    assert "Ash" in captured["messages"][0]["content"]


def test_chat_rejects_empty_message():
    assert client.post("/v1/chat", json={"message": "   "}).status_code == 400


def test_tts_without_key_is_503(monkeypatch):
    monkeypatch.setattr(phone_api, "_xai_key", lambda: None)
    assert client.post("/v1/tts", json={"text": "hello"}).status_code == 503


def test_stt_transcribes_verbatim(monkeypatch):
    # Whisper output passes through untouched — no censorship layer.
    monkeypatch.setattr(
        phone_api, "transcribe_file", lambda path, **kw: "well, fuck me sideways"
    )
    r = client.post(
        "/v1/stt", files={"audio": ("clip.wav", b"RIFFfakewav", "audio/wav")}
    )
    assert r.status_code == 200
    assert r.json() == {"text": "well, fuck me sideways"}


def test_stt_without_mlx_whisper_is_503(monkeypatch):
    def boom(path, **kw):
        raise RuntimeError("mlx-whisper is not installed")

    monkeypatch.setattr(phone_api, "transcribe_file", boom)
    r = client.post(
        "/v1/stt", files={"audio": ("clip.wav", b"RIFFfakewav", "audio/wav")}
    )
    assert r.status_code == 503


def test_stt_rejects_empty_upload():
    r = client.post("/v1/stt", files={"audio": ("clip.wav", b"", "audio/wav")})
    assert r.status_code == 400


def _stream_events(payload):
    with client.stream("POST", "/v1/chat/stream", json=payload) as r:
        assert r.status_code == 200
        return [json.loads(line) for line in r.iter_lines() if line]


def test_stream_tokens_then_done(monkeypatch):
    chunks = ["One. ", "Two ", "three."]
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(chunks))
    monkeypatch.setattr(
        phone_api, "_synthesize", lambda text, voice=None, speed=None: (f"[{text}]".encode(), "audio/mpeg")
    )
    events = _stream_events({"message": "hey"})

    assert events[0]["type"] == "state"
    assert "warmth" in events[0]["state"]

    deltas = [e["text"] for e in events if e["type"] == "delta"]
    assert deltas == chunks  # tokens pass through verbatim, in order

    assert events[-1]["type"] == "done"
    assert events[-1]["reply"] == "One. Two three."


def test_stream_speaks_first_sentence_early(monkeypatch):
    chunks = ["One. ", "Two ", "three."]
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(chunks))
    monkeypatch.setattr(
        phone_api, "_synthesize", lambda text, voice=None, speed=None: (f"[{text}]".encode(), "audio/mpeg")
    )
    events = _stream_events({"message": "hey"})

    audio = [e for e in events if e["type"] == "audio"]
    assert len(audio) == 2
    # First clip is just the first sentence — voice starts before the reply ends.
    assert audio[0]["seq"] == 0
    assert audio[0]["text"] == "One."
    assert base64.b64decode(audio[0]["audio_b64"]) == b"[One.]"
    # The remainder is spoken as a follow-up clip.
    assert audio[1]["text"] == "Two three."
    # The first clip must be scheduled before the final delta finishes.
    types = [e["type"] for e in events]
    assert types.index("audio") < types.index("done")


def test_stream_without_voice_still_streams(monkeypatch):
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(["mm."]))
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)
    events = _stream_events({"message": "hey"})
    assert [e["type"] for e in events if e["type"] == "audio"] == []
    assert events[-1]["type"] == "done"


def test_stream_surfaces_model_errors(monkeypatch):
    def boom(**kw):
        raise RuntimeError("ollama is down")
        yield  # pragma: no cover

    monkeypatch.setattr(phone_api, "stream_chat", boom)
    events = _stream_events({"message": "hey"})
    assert events[-1]["type"] == "error"
    assert "ollama is down" in events[-1]["detail"]


def test_stream_rejects_empty_message():
    r = client.post("/v1/chat/stream", json={"message": "  "})
    assert r.status_code == 400


def test_persona_override_replaces_vesper_prompt(monkeypatch):
    captured = {}

    def spy_stream(**kw):
        captured.update(kw)
        yield "roger that."

    monkeypatch.setattr(phone_api, "stream_chat", spy_stream)
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)
    r = client.post(
        "/v1/chat",
        json={
            "message": "hey",
            "persona_override": "You are Mika, a bright pilot.",
            "plain": True,
            "user_name": "Ash",
        },
    )
    assert r.status_code == 200
    system = captured["messages"][0]["content"]
    assert system.startswith("You are Mika")
    assert "Vesper" not in system
    assert "Ash" in system


def test_plain_skips_emotion_drift(monkeypatch):
    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(["ok."]))
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)
    sent = {"warmth": 0.5, "sadism": 0.5}
    r = client.post(
        "/v1/chat",
        json={
            "message": "I love you and I feel safe with you.",
            "persona_override": "You are a concise assistant.",
            "plain": True,
            "state": sent,
        },
    )
    body = r.json()
    # Affectionate text would normally raise warmth; plain passes state through.
    assert body["state"]["warmth"] == 0.5


def test_tts_endpoint_voice_passthrough(monkeypatch):
    seen = {}

    def fake_synth(text, voice=None, speed=None):
        seen["voice"] = voice
        return (b"take2", "audio/mpeg")

    monkeypatch.setattr(phone_api, "_synthesize", fake_synth)
    r = client.post("/v1/tts", json={"text": "again, differently", "voice": "eve"})
    assert r.status_code == 200
    assert seen["voice"] == "eve"
    assert base64.b64decode(r.json()["audio_b64"]) == b"take2"


def test_override_vibe_rider(monkeypatch):
    captured = {}

    def spy_stream(**kw):
        captured.update(kw)
        yield "roger."

    monkeypatch.setattr(phone_api, "stream_chat", spy_stream)
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)

    # Mika (non-plain override): her sliders reach the prompt as a vibe line.
    client.post(
        "/v1/chat",
        json={
            "message": "hey",
            "persona_override": "You are Mika.",
            "state": {"warmth": 0.9, "playfulness": 0.8},
        },
    )
    system = captured["messages"][0]["content"]
    assert "Current vibe" in system
    assert "warmth 0.90" in system

    # Plain Chat stays vibe-free.
    client.post(
        "/v1/chat",
        json={"message": "hey", "persona_override": "You are an assistant.", "plain": True},
    )
    assert "Current vibe" not in captured["messages"][0]["content"]


def test_reply_style_riders(monkeypatch):
    captured = {}

    def spy_stream(**kw):
        captured.update(kw)
        yield "mm."

    monkeypatch.setattr(phone_api, "stream_chat", spy_stream)
    monkeypatch.setattr(phone_api, "_synthesize", lambda text, voice=None, speed=None: None)

    client.post("/v1/chat", json={"message": "hey", "reply_style": "narrative"})
    assert "Reply style: narrative" in captured["messages"][0]["content"]

    client.post("/v1/chat", json={"message": "hey", "reply_style": "chat"})
    assert "Reply style: chat" in captured["messages"][0]["content"]

    # Absent style leaves the prompt untouched; overrides get the rider too.
    client.post("/v1/chat", json={"message": "hey"})
    assert "Reply style" not in captured["messages"][0]["content"]

    client.post(
        "/v1/chat",
        json={"message": "hey", "persona_override": "You are Mika.", "reply_style": "narrative"},
    )
    assert captured["messages"][0]["content"].startswith("You are Mika.")
    assert "Reply style: narrative" in captured["messages"][0]["content"]


def test_voice_override_reaches_tts(monkeypatch):
    seen = {}

    def fake_synth(text, voice=None, speed=None):
        seen["voice"] = voice
        return (b"clip", "audio/mpeg")

    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(["hi there."]))
    monkeypatch.setattr(phone_api, "_synthesize", fake_synth)
    r = client.post("/v1/chat", json={"message": "hey", "voice": "eve"})
    assert r.status_code == 200
    assert seen["voice"] == "eve"


def test_mika_live_relay(monkeypatch):
    captured = {}

    def fake_turn(**kw):
        captured.update(kw)
        return "wheels up."

    monkeypatch.setattr(phone_api, "resolve_webhook", lambda: ("https://wh", "sekret"))
    monkeypatch.setattr(phone_api, "resolve_reply_base", lambda: "https://mac.tailnet.ts.net")
    monkeypatch.setattr(phone_api, "ensure_reply_listener", lambda port: True)
    monkeypatch.setattr(phone_api, "live_turn", fake_turn)

    r = client.post(
        "/v1/mika/live",
        json={"message": "hey mika", "warmth": 0.9, "sadism": 0.2, "intensity": 0.6},
    )
    assert r.status_code == 200
    assert r.json() == {"reply": "wheels up."}
    assert captured["webhook_url"] == "https://wh"
    assert captured["reply_base"] == "https://mac.tailnet.ts.net"
    assert captured["warmth"] == 0.9

    # Phone-supplied credentials win over the Mac files.
    client.post(
        "/v1/mika/live",
        json={"message": "hey", "webhook_url": "https://phone-wh", "webhook_key": "pk"},
    )
    assert captured["webhook_url"] == "https://phone-wh"
    assert captured["webhook_key"] == "pk"


def test_mika_live_unconfigured_is_503(monkeypatch):
    monkeypatch.setattr(phone_api, "resolve_webhook", lambda: (None, None))
    r = client.post("/v1/mika/live", json={"message": "hey"})
    assert r.status_code == 503


def test_mika_live_turn_roundtrip(monkeypatch):
    import threading

    from companion import mika_live

    def fake_post(url, json=None, headers=None, timeout=None):
        assert json["replyUrl"].endswith("/reply")
        assert headers["X-Automation-Key"] == "k"
        threading.Timer(0.05, lambda: mika_live.deliver(json["turnId"], "pong")).start()

        class R:
            def raise_for_status(self):
                pass

        return R()

    monkeypatch.setattr(mika_live.httpx, "post", fake_post)
    reply = mika_live.live_turn(
        webhook_url="https://wh",
        webhook_key="k",
        text="hi",
        warmth=0.5,
        sadism=0.5,
        intensity=0.5,
        reply_base="https://base",
        timeout=2,
    )
    assert reply == "pong"


def test_voice_intensity_maps_to_tts_speed(monkeypatch):
    seen = {}

    def fake_synth(text, voice=None, speed=None):
        seen["speed"] = speed
        return (b"clip", "audio/mpeg")

    monkeypatch.setattr(phone_api, "stream_chat", lambda **kw: iter(["hi there."]))
    monkeypatch.setattr(phone_api, "_synthesize", fake_synth)
    r = client.post(
        "/v1/chat",
        json={"message": "hey", "voice_intensity": 1.0, "voice_heat": 0.9, "tts_engine": "ara"},
    )
    assert r.status_code == 200
    assert seen["speed"] == 1.25  # 0.85 + 0.4 * 1.0

    r = client.post("/v1/tts", json={"text": "hello", "voice_intensity": 0.0})
    assert r.status_code == 200
    assert seen["speed"] == 0.85
