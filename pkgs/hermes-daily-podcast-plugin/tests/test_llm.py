"""Unit tests for the LLM client error normalization and thinking control.

All tests are hermetic and stdlib-only: httpx is replaced by a fake module
injected into sys.modules, or `_post` is monkeypatched directly. The
behaviors under test exist because of a production incident where
`httpx.ReadTimeout` escaped `_post` un-normalized and crashed episode
generation for a whole topic (score.py only catches LlmError).
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.llm as llm  # noqa: E402


def _fake_httpx(
    *,
    raise_exc: type[Exception] | None = None,
    status_code: int = 200,
    content: bytes = b"{}",
) -> types.ModuleType:
    """Build a stand-in httpx module with the exception hierarchy we rely on."""
    mod = types.ModuleType("httpx")

    class HTTPError(Exception):
        pass

    class ReadTimeout(HTTPError):
        pass

    class ConnectError(HTTPError):
        pass

    mod.HTTPError = HTTPError
    mod.ReadTimeout = ReadTimeout
    mod.ConnectError = ConnectError

    class _Resp:
        def __init__(self) -> None:
            self.status_code = status_code
            self.content = content
            self.text = content.decode("utf-8", "replace")

    def post(url, **kwargs):
        if raise_exc is not None:
            raise raise_exc("timed out")
        return _Resp()

    mod.post = post
    return mod


def _chat_response(content: str) -> bytes:
    return json.dumps(
        {"choices": [{"message": {"content": content}}]}
    ).encode("utf-8")


class TestPostErrorNormalization:
    def test_read_timeout_becomes_llm_error(self, monkeypatch):
        fake = _fake_httpx(raise_exc=None)
        fake_with_exc = _fake_httpx()
        fake_with_exc.post = lambda url, **kw: (_ for _ in ()).throw(
            fake_with_exc.ReadTimeout("timed out")
        )
        monkeypatch.setitem(sys.modules, "httpx", fake_with_exc)
        with pytest.raises(llm.LlmError, match="ReadTimeout"):
            llm._post("http://ai/v1/chat/completions", b"{}", {}, 1.0)

    def test_connect_error_becomes_llm_error(self, monkeypatch):
        fake = _fake_httpx()
        fake.post = lambda url, **kw: (_ for _ in ()).throw(
            fake.ConnectError("refused")
        )
        monkeypatch.setitem(sys.modules, "httpx", fake)
        with pytest.raises(llm.LlmError, match="ConnectError"):
            llm._post("http://ai/v1/chat/completions", b"{}", {}, 1.0)

    def test_http_error_status_becomes_llm_error(self, monkeypatch):
        fake = _fake_httpx(status_code=502, content=b"bad gateway")
        monkeypatch.setitem(sys.modules, "httpx", fake)
        with pytest.raises(llm.LlmError, match="502"):
            llm._post("http://ai/v1/chat/completions", b"{}", {}, 1.0)

    def test_success_returns_body(self, monkeypatch):
        fake = _fake_httpx(content=b'{"ok": true}')
        monkeypatch.setitem(sys.modules, "httpx", fake)
        assert llm._post("http://x", b"{}", {}, 1.0) == b'{"ok": true}'


class TestChatJsonThinkStripping:
    def test_strips_think_block(self, monkeypatch):
        monkeypatch.setattr(
            llm,
            "_post",
            lambda *a, **kw: _chat_response(
                '<think>ちょっと考える…</think>{"scores": []}'
            ),
        )
        assert llm.chat_json([{"role": "user", "content": "x"}]) == {"scores": []}

    def test_strips_multiline_think_block(self, monkeypatch):
        monkeypatch.setattr(
            llm,
            "_post",
            lambda *a, **kw: _chat_response(
                '<think>\nline1\nline2\n</think>\n{"a": 1}'
            ),
        )
        assert llm.chat_json([{"role": "user", "content": "x"}]) == {"a": 1}

    def test_empty_response_raises_llm_error(self, monkeypatch):
        monkeypatch.setattr(llm, "_post", lambda *a, **kw: _chat_response(""))
        with pytest.raises(llm.LlmError, match="valid JSON"):
            llm.chat_json([{"role": "user", "content": "x"}])

    def test_all_think_no_payload_raises_llm_error(self, monkeypatch):
        """max_tokens exhausted mid-thought → nothing usable after stripping."""
        monkeypatch.setattr(
            llm,
            "_post",
            lambda *a, **kw: _chat_response("<think>延々と考えて終わる</think>"),
        )
        with pytest.raises(llm.LlmError, match="valid JSON"):
            llm.chat_json([{"role": "user", "content": "x"}])


class TestDisableThinking:
    def _capture_post(self, monkeypatch) -> dict[str, Any]:
        captured: dict[str, Any] = {}

        def fake_post(url, payload, headers, timeout):
            captured["body"] = json.loads(payload.decode("utf-8"))
            return _chat_response('{"scores": []}')

        monkeypatch.setattr(llm, "_post", fake_post)
        return captured

    def test_appends_no_think_and_think_false(self, monkeypatch):
        captured = self._capture_post(monkeypatch)
        llm.chat(
            [
                {"role": "system", "content": "あなたは編集者です。"},
                {"role": "user", "content": "採点して"},
            ],
            disable_thinking=True,
        )
        body = captured["body"]
        assert body["think"] is False
        assert body["messages"][0]["content"].endswith("/no_think")

    def test_prepends_system_when_missing(self, monkeypatch):
        captured = self._capture_post(monkeypatch)
        llm.chat([{"role": "user", "content": "採点して"}], disable_thinking=True)
        body = captured["body"]
        assert body["messages"][0]["role"] == "system"
        assert "/no_think" in body["messages"][0]["content"]

    def test_does_not_mutate_caller_messages(self, monkeypatch):
        self._capture_post(monkeypatch)
        messages = [{"role": "system", "content": "original"}]
        llm.chat(messages, disable_thinking=True)
        assert messages == [{"role": "system", "content": "original"}]

    def test_off_by_default(self, monkeypatch):
        captured = self._capture_post(monkeypatch)
        llm.chat([{"role": "user", "content": "x"}])
        assert "think" not in captured["body"]
