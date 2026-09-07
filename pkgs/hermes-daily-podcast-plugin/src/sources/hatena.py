"""はてなブックマーク fetcher.

3 通りの絞り込みをサポート (優先順位は tags > query > category):

- `tags = ["模型", "プラモデル", ...]` — タグ検索 (推奨)。タグごとに別々の
  RSS を取得し、結果をマージ。タグ一致は title だけでなく「実際にそのタグが
  付与された記事」に絞れるので、キーワード曖昧検索よりノイズが少ない。
  `/q/<タグ>` を直接叩く: 旧 `search/tag` エンドポイントは `/q/` へ 301 され、
  その際 `users` / `date_begin` 等の絞り込みパラメータが全て落とされる
  (= 実質「過去数年の人気記事」固定になる) ため使ってはいけない。
  `date_begin` (YYYY-MM-DD) は明示指定 > handlers が注入する `since_date`
  (前回生成日 − 2 日) の順で採用。
- `query = "ガンプラ"` — フリーキーワード検索 (`search.rss?q=...`)。タイトル /
  本文 / タグの全文一致。誤マッチが出ることもある。
- `category = "fun"` — `hotentry/<category>.rss` でカテゴリ別ホットエントリ。
  範囲が広いのでホビー特化トピックには向かない (政治・芸能等が混入)。

カテゴリスラッグ (2026 年現在の安定形):
  general, social, economics, life, knowledge, it, fun, entertainment, game
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from typing import Any

from . import register
from .. import config as cfg
from .. import http

logger = logging.getLogger(__name__)

HOTENTRY_URL = "https://b.hatena.ne.jp/hotentry/{category}.rss"
SEARCH_URL = "https://b.hatena.ne.jp/search.rss"
TAG_SEARCH_URL = "https://b.hatena.ne.jp/q/{tag}"

# 母数優先: ニッチタグは users>=3 だと月 1 件レベルまで痩せる。品質・ジャンル
# の選別は LLM 採点の仕事なので、fetcher は広く拾う。
DEFAULT_MIN_USERS = 1


@register("hatena")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    tags_raw = source.extra.get("tags") or source.extra.get("tag")
    category = (source.extra.get("category") or "").strip()
    query = (source.extra.get("query") or "").strip()
    min_users = int(source.extra.get("min_users", DEFAULT_MIN_USERS))
    date_begin = str(
        source.extra.get("date_begin") or source.extra.get("since_date") or ""
    ).strip()
    if date_begin and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date_begin):
        logger.warning(
            "daily-podcast hatena: ignoring malformed date_begin=%r "
            "(expected YYYY-MM-DD)",
            date_begin,
        )
        date_begin = ""

    # Normalize tags into a list of clean strings.
    tags: list[str] = []
    if isinstance(tags_raw, str):
        tags = [tags_raw.strip()] if tags_raw.strip() else []
    elif isinstance(tags_raw, list):
        tags = [str(t).strip() for t in tags_raw if str(t).strip()]

    if tags:
        return _fetch_tags(tags, min_users, date_begin or None)
    if query:
        try:
            raw = http.get_bytes(
                SEARCH_URL, params={"q": query, "users": str(min_users)}
            )
        except http.HttpError as exc:
            logger.warning("daily-podcast hatena search: %s", exc)
            return []
        return _parse_feed(raw)
    if category:
        try:
            raw = http.get_bytes(HOTENTRY_URL.format(category=category))
        except http.HttpError as exc:
            logger.warning("daily-podcast hatena hotentry: %s", exc)
            return []
        return _parse_feed(raw)

    logger.warning(
        "daily-podcast hatena: source needs 'tags', 'query', or 'category'"
    )
    return []


def _fetch_tags(
    tags: list[str],
    min_users: int,
    date_begin: str | None = None,
) -> list[dict[str, Any]]:
    """Fetch one RSS feed per tag and merge, dropping per-URL duplicates.

    Hits `/q/<tag>` directly — the legacy `search/tag` endpoint redirects
    here anyway but drops every filter param on the way.
    """
    from urllib.parse import quote

    seen_urls: set[str] = set()
    merged: list[dict[str, Any]] = []
    for tag in tags:
        params: dict[str, str] = {
            "target": "tag",
            "mode": "rss",
            "users": str(min_users),
            "sort": "recent",
        }
        if date_begin:
            params["date_begin"] = date_begin
        try:
            raw = http.get_bytes(
                TAG_SEARCH_URL.format(tag=quote(tag, safe="")),
                params=params,
            )
        except http.HttpError as exc:
            logger.warning("daily-podcast hatena tag=%s: %s", tag, exc)
            continue
        for item in _parse_feed(raw):
            url = item.get("url")
            if not url or url in seen_urls:
                continue
            seen_urls.add(url)
            item.setdefault("matched_tag", tag)
            merged.append(item)
    return merged


def _parse_feed(raw: bytes) -> list[dict[str, Any]]:
    """Parse RDF/RSS via feedparser; fall back to stdlib XML for resilience."""
    try:
        import feedparser

        parsed = feedparser.parse(raw)
        entries = parsed.entries or []
    except ImportError:
        return _parse_feed_stdlib(raw)

    out: list[dict[str, Any]] = []
    for e in entries:
        url = e.get("link") or e.get("id") or ""
        title = (e.get("title") or "").strip()
        if not url or not title:
            continue
        summary = (e.get("summary") or "").strip()
        out.append(
            {
                "url": url,
                "title": title,
                "summary": summary[:500],
                "points": _coerce_int(e.get("hatena_bookmarkcount"))
                or _coerce_int(e.get("bookmarkcount")),
                "published_at": _normalize_ts(
                    e.get("published") or e.get("dc_date") or e.get("updated")
                ),
                "language_hint": "ja",
            }
        )
    return out


def _parse_feed_stdlib(raw: bytes) -> list[dict[str, Any]]:
    """Minimal RDF item extraction without feedparser."""
    import xml.etree.ElementTree as ET

    ns = {
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rss": "http://purl.org/rss/1.0/",
        "dc": "http://purl.org/dc/elements/1.1/",
        "hatena": "http://www.hatena.ne.jp/info/xmlns#",
    }
    try:
        root = ET.fromstring(raw)
    except ET.ParseError as exc:
        logger.warning("daily-podcast hatena: XML parse failed: %s", exc)
        return []

    out: list[dict[str, Any]] = []
    for item in root.findall("rss:item", ns):
        link = (item.findtext("rss:link", default="", namespaces=ns) or "").strip()
        title = (item.findtext("rss:title", default="", namespaces=ns) or "").strip()
        if not link or not title:
            continue
        summary = (
            item.findtext("rss:description", default="", namespaces=ns) or ""
        ).strip()
        out.append(
            {
                "url": link,
                "title": title,
                "summary": summary[:500],
                "points": _coerce_int(
                    item.findtext("hatena:bookmarkcount", namespaces=ns)
                ),
                "published_at": _normalize_ts(
                    item.findtext("dc:date", namespaces=ns)
                ),
                "language_hint": "ja",
            }
        )
    return out


def _coerce_int(v: Any) -> int | None:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _normalize_ts(s: Any) -> str | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00")).astimezone(
            timezone.utc
        ).isoformat()
    except ValueError:
        return str(s)
