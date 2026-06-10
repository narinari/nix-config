"""Tests for the vendored last30days http layer.

We exercise the three things the upstream module gives us over the previous
single-shot httpx wrapper: 429 + Retry-After backoff, DNS gaierror retry
budget expansion, and secret masking in debug logs.
"""

from __future__ import annotations

import importlib
import io
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path
from unittest.mock import MagicMock

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from src._vendor.last30days import http as vendor_http  # noqa: E402


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _fast_sleep(monkeypatch):
    monkeypatch.setattr(vendor_http.time, "sleep", lambda *_a, **_k: None)


def _make_response(body: bytes = b'{"ok":true}', status: int = 200):
    resp = MagicMock()
    resp.read.return_value = body
    resp.status = status
    resp.__enter__ = MagicMock(return_value=resp)
    resp.__exit__ = MagicMock(return_value=False)
    return resp


def _make_http_error(code: int, *, retry_after: str | None = None, body: bytes = b""):
    headers: dict[str, str] = {}
    if retry_after is not None:
        headers["Retry-After"] = retry_after
    return urllib.error.HTTPError(
        url="http://example.com",
        code=code,
        msg="error",
        hdrs=headers,  # type: ignore[arg-type]
        fp=io.BytesIO(body),
    )


# ---------------------------------------------------------------------------
# 429 / Retry-After
# ---------------------------------------------------------------------------


def test_request_retries_after_429_then_succeeds(monkeypatch):
    calls: list[str] = []

    def fake_urlopen(req, timeout=None):
        calls.append(req.full_url)
        if len(calls) == 1:
            raise _make_http_error(429, retry_after="0")
        return _make_response()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = vendor_http.request("GET", "https://example.com/x", retries=3)
    assert result == {"ok": True}
    assert len(calls) == 2


def test_request_gives_up_after_max_429(monkeypatch):
    def fake_urlopen(req, timeout=None):
        raise _make_http_error(429)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    with pytest.raises(vendor_http.HTTPError) as exc_info:
        vendor_http.request("GET", "https://example.com/x", max_429_retries=2)
    assert exc_info.value.status_code == 429


def test_request_does_not_retry_other_4xx(monkeypatch):
    calls: list[str] = []

    def fake_urlopen(req, timeout=None):
        calls.append(req.full_url)
        raise _make_http_error(404)

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    with pytest.raises(vendor_http.HTTPError) as exc_info:
        vendor_http.request("GET", "https://example.com/x", retries=5)
    assert exc_info.value.status_code == 404
    assert len(calls) == 1


# ---------------------------------------------------------------------------
# DNS gaierror expansion
# ---------------------------------------------------------------------------


def test_dns_failure_expands_retry_budget(monkeypatch):
    """A caller passing `retries=1` still gets MIN_DNS_RETRIES attempts on gaierror."""
    calls: list[int] = []

    def fake_urlopen(req, timeout=None):
        calls.append(1)
        if len(calls) < vendor_http.MIN_DNS_RETRIES:
            raise urllib.error.URLError(socket.gaierror("Name or service not known"))
        return _make_response()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = vendor_http.request("GET", "https://example.com/x", retries=1)
    assert result == {"ok": True}
    assert len(calls) == vendor_http.MIN_DNS_RETRIES


def test_non_dns_url_error_respects_caller_retries(monkeypatch):
    """ConnectionRefused doesn't widen the budget like DNS does."""
    calls: list[int] = []

    def fake_urlopen(req, timeout=None):
        calls.append(1)
        raise urllib.error.URLError("Connection refused")

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    with pytest.raises(vendor_http.HTTPError):
        vendor_http.request("GET", "https://example.com/x", retries=1)
    assert len(calls) == 1


# ---------------------------------------------------------------------------
# Secret masking
# ---------------------------------------------------------------------------


def test_secret_masking_redacts_api_key(monkeypatch, capsys):
    """Sensitive query params are redacted in the debug log."""
    monkeypatch.setenv("HERMES_PODCAST_VENDOR_DEBUG", "1")
    from src._vendor.last30days import log as vendor_log

    importlib.reload(vendor_log)
    importlib.reload(vendor_http)

    monkeypatch.setattr(vendor_http.time, "sleep", lambda *_a, **_k: None)
    monkeypatch.setattr(
        urllib.request, "urlopen", lambda req, timeout=None: _make_response()
    )

    vendor_http.request(
        "GET", "https://example.com/x?api_key=SECRET&token=ALSOSECRET&q=foo"
    )
    captured = capsys.readouterr()
    assert "SECRET" not in captured.err
    assert "ALSOSECRET" not in captured.err
    assert "api_key=***" in captured.err
    assert "token=***" in captured.err
    # Non-sensitive params are kept
    assert "q=foo" in captured.err
