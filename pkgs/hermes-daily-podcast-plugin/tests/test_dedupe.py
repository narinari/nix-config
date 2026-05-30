"""Unit tests for the dedupe utilities.

These cover the boundary cases that produced false positives or misses in
manual smoke runs: tracking-param-only URL diffs, www-prefix mismatch,
title trailing publisher attribution.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow `import src` from the test runner without packaging the plugin first.
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

import src.dedupe as dedupe  # noqa: E402


class TestNormalizeUrl:
    def test_drops_utm_params(self):
        a = "https://example.com/post?utm_source=newsletter&utm_medium=email"
        b = "https://example.com/post"
        assert dedupe.normalize_url(a) == dedupe.normalize_url(b)

    def test_strips_leading_www(self):
        assert dedupe.normalize_url("https://www.example.com/x") == dedupe.normalize_url(
            "https://example.com/x"
        )

    def test_drops_fragment_and_trailing_slash(self):
        a = "https://example.com/post/"
        b = "https://example.com/post#section"
        assert dedupe.normalize_url(a) == dedupe.normalize_url(b)

    def test_keeps_meaningful_query(self):
        a = "https://example.com/search?q=ai"
        b = "https://example.com/search?q=ml"
        assert dedupe.normalize_url(a) != dedupe.normalize_url(b)


class TestTitleDedupe:
    def test_strips_trailing_publisher(self):
        a = "What's new in qwen3.6 - The Verge"
        b = "What's new in qwen3.6"
        assert dedupe.normalize_title(a) == dedupe.normalize_title(b)

    def test_jaro_similar_titles_collide(self):
        seen = [("https://other.test", "Why Qwen3.6 Beats GPT in Japanese")]
        assert dedupe.is_duplicate(
            "https://example.com/new",
            "Why Qwen 3.6 Beats GPT in Japanese!",
            seen,
        )

    def test_exact_url_match_dominates(self):
        norm = dedupe.normalize_url("https://example.com/a?utm_source=x")
        seen = [(norm, "Totally different title")]
        assert dedupe.is_duplicate(
            "https://example.com/a", "Something else entirely", seen
        )

    def test_unrelated_items_are_not_duplicates(self):
        seen = [("https://a.test", "Tamiya releases new acrylic paints")]
        assert not dedupe.is_duplicate(
            "https://b.test",
            "Bandai launches HG Gundam Aerial Rebuild",
            seen,
        )
