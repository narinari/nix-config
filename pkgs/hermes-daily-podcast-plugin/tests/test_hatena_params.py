"""Request-shape tests for the hatena tag fetcher.

Background: the legacy `/search/tag` endpoint 301-redirects to `/q/<tag>`
and hatena drops every filter param (`users`, `date_range`, ...) in that
redirect — the fetcher silently degraded to "top ~20 articles of the last
several years", which is why the same candidates surfaced every night.
The fetcher must therefore hit `/q/<tag>` directly with explicit params.

`http.get_bytes` is monkeypatched; the canned response exercises the
stdlib RDF parser (feedparser is absent in the pytest env).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.config as cfg  # noqa: E402
import src.sources.hatena as hatena  # noqa: E402

RDF_ONE_ITEM = b"""<?xml version="1.0" encoding="utf-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
         xmlns="http://purl.org/rss/1.0/"
         xmlns:dc="http://purl.org/dc/elements/1.1/"
         xmlns:hatena="http://www.hatena.ne.jp/info/xmlns#">
<item rdf:about="https://example.com/a">
<title>\xe8\xa8\x98\xe4\xba\x8bA</title>
<link>https://example.com/a</link>
<description>desc</description>
<dc:date>2026-09-01T00:00:00Z</dc:date>
<hatena:bookmarkcount>5</hatena:bookmarkcount>
</item>
</rdf:RDF>
"""


def _capture_get_bytes(monkeypatch) -> list[dict[str, Any]]:
    calls: list[dict[str, Any]] = []

    def fake(url, *, params=None, headers=None, timeout=None):
        calls.append({"url": url, "params": dict(params or {})})
        return RDF_ONE_ITEM

    monkeypatch.setattr(hatena.http, "get_bytes", fake)
    return calls


def _source(extra: dict[str, Any]) -> cfg.SourceConfig:
    return cfg.SourceConfig(type="hatena", extra=extra)


class TestTagRequestShape:
    def test_hits_q_endpoint_directly_with_filters(self, monkeypatch):
        calls = _capture_get_bytes(monkeypatch)
        hatena.fetch(_source({"tags": ["模型"], "min_users": 3}))
        assert len(calls) == 1
        assert calls[0]["url"] == f"https://b.hatena.ne.jp/q/{quote('模型')}"
        assert calls[0]["params"]["target"] == "tag"
        assert calls[0]["params"]["users"] == "3"
        assert calls[0]["params"]["sort"] == "recent"
        assert calls[0]["params"]["mode"] == "rss"

    def test_min_users_defaults_to_one(self, monkeypatch):
        """Volume over popularity: genre/quality filtering is the LLM
        scorer's job, the fetcher should not starve it of candidates."""
        calls = _capture_get_bytes(monkeypatch)
        hatena.fetch(_source({"tags": ["模型"]}))
        assert calls[0]["params"]["users"] == "1"

    def test_injected_since_date_becomes_date_begin(self, monkeypatch):
        calls = _capture_get_bytes(monkeypatch)
        hatena.fetch(_source({"tags": ["模型"], "since_date": "2026-08-25"}))
        assert calls[0]["params"]["date_begin"] == "2026-08-25"

    def test_explicit_date_begin_wins_over_since_date(self, monkeypatch):
        calls = _capture_get_bytes(monkeypatch)
        hatena.fetch(
            _source(
                {
                    "tags": ["模型"],
                    "date_begin": "2026-01-01",
                    "since_date": "2026-08-25",
                }
            )
        )
        assert calls[0]["params"]["date_begin"] == "2026-01-01"

    def test_no_date_begin_when_neither_present(self, monkeypatch):
        calls = _capture_get_bytes(monkeypatch)
        hatena.fetch(_source({"tags": ["模型"]}))
        assert "date_begin" not in calls[0]["params"]

    def test_parses_items_and_dedups_across_tags(self, monkeypatch):
        _capture_get_bytes(monkeypatch)
        items = hatena.fetch(_source({"tags": ["模型", "プラモデル"]}))
        # 両タグが同じ URL を返す → 1 件にマージ
        assert len(items) == 1
        assert items[0]["url"] == "https://example.com/a"
        assert items[0]["points"] == 5
