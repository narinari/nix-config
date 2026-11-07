import io
import json
import urllib.error

import pytest

from plamo_html.client import HttpClient, max_tokens_for
from plamo_html.errors import InputError, ServerError, ServerUnreachable
from plamo_html.glossary import parse_glossary
from plamo_html.prompt import GlossaryEntry, Pair, build_prompt


def test_prompt_exact_with_history_and_glossary():
    got = build_prompt(
        context="C",
        history=[Pair("a", "あ")],
        glossary=[GlossaryEntry("x", "え"), GlossaryEntry("y", "い")],
        src="Hello",
        form="polite",
    )
    want = (
        "<|plamo:tag|>dataset<|plamo:msg|>translation"
        "<|plamo:tag|>context<|plamo:msg|>C"
        "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>a"
        "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:msg|>あ"
        "<|plamo:tag|>glossary<|plamo:index|>x<|plamo:item|>え<|plamo:index|>y<|plamo:item|>い"
        "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>Hello"
        "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja<|plamo:key|>form<|plamo:val|>polite<|plamo:msg|>"
    )
    assert got == want


def test_prompt_minimal():
    got = build_prompt(context="C", history=[], glossary=[], src="Hi", form="plain")
    assert got.startswith("<|plamo:tag|>dataset<|plamo:msg|>translation<|plamo:tag|>context<|plamo:msg|>C<|plamo:tag|>input")
    assert "glossary" not in got


def test_glossary_parse_ok_and_errors():
    assert parse_glossary('[{"source":"a","target":"b"}]') == (GlossaryEntry("a", "b"),)
    for bad in ["{", "{}", "[1]", '[{"source":"a"}]', '[{"source":"","target":"b"}]']:
        with pytest.raises(InputError):
            parse_glossary(bad)


def test_max_tokens():
    assert max_tokens_for("a" * 10) == 158
    assert max_tokens_for("a" * 5000) == 2048


class _Resp(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def _ok(text="  訳  "):
    return _Resp(json.dumps({"choices": [{"text": text}]}).encode())


def test_http_success_and_request_shape(monkeypatch):
    seen = {}

    def fake(req, timeout):
        seen["body"] = json.loads(req.data)
        seen["url"] = req.full_url
        seen["timeout"] = timeout
        return _ok()

    monkeypatch.setattr("urllib.request.urlopen", fake)
    assert HttpClient("http://h:1/").complete("P", 10) == "訳"
    assert seen["url"] == "http://h:1/v1/completions" and seen["timeout"] == 180
    assert seen["body"] == {
        "model": "plamo-3-translate",
        "prompt": "P",
        "temperature": 0,
        "max_tokens": 10,
        "stop": ["<|plamo:tag|>", "<|plamo:bos|>"],
    }


def test_http_transient_then_success_and_exhaustion(monkeypatch):
    sleeps = []
    responses = [urllib.error.HTTPError("u", 503, "x", {}, None), TimeoutError(), _ok("良")]

    def fake(req, timeout):
        r = responses.pop(0)
        if isinstance(r, Exception):
            raise r
        return r

    monkeypatch.setattr("urllib.request.urlopen", fake)
    assert HttpClient("http://h", sleep=sleeps.append).complete("P", 1) == "良"
    assert sleeps == [2.0, 4.0]

    def always(req, timeout):
        raise urllib.error.HTTPError("u", 503, "x", {}, None)

    monkeypatch.setattr("urllib.request.urlopen", always)
    with pytest.raises(ServerError):
        HttpClient("http://h", sleep=lambda s: None).complete("P", 1)


def test_http_unreachable_and_client_error(monkeypatch):
    def refused(req, timeout):
        raise urllib.error.URLError(ConnectionRefusedError())

    monkeypatch.setattr("urllib.request.urlopen", refused)
    with pytest.raises(ServerUnreachable):
        HttpClient("http://h").complete("P", 1)

    def bad(req, timeout):
        raise urllib.error.HTTPError("u", 400, "x", {}, None)

    monkeypatch.setattr("urllib.request.urlopen", bad)
    with pytest.raises(ServerError):
        HttpClient("http://h").complete("P", 1)

    monkeypatch.setattr("urllib.request.urlopen", lambda r, timeout: _Resp(b"not json"))
    with pytest.raises(ServerError):
        HttpClient("http://h").complete("P", 1)
