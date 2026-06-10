"""X / Twitter fetcher via xAI Live Search.

xAI's chat/completions endpoint can attach a Live Search pass over X posts
when ``search_parameters`` is supplied. We ask the model to return a JSON
array of posts so the rest of the pipeline can treat them like any other
source. Browser-cookie / official-API alternatives are intentionally not
supported here — they don't work cleanly on a Linux server.

The fetcher logs a warning and returns ``[]`` whenever:

- ``XAI_API_KEY`` is unset (so the host can opt out simply by not
  provisioning a secret),
- the upstream call fails for any reason,
- the model returns prose instead of a JSON array (the strict prompt makes
  this rare but not impossible).
"""

from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

from . import register
from .. import config as cfg
from .. import http
from ._common import normalize_ts, truncate

logger = logging.getLogger(__name__)

XAI_CHAT_URL = "https://api.x.ai/v1/chat/completions"
DEFAULT_MODEL = "grok-3-latest"


@register("x")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast x: source missing 'query'")
        return []

    api_key = (os.environ.get("XAI_API_KEY") or "").strip()
    if not api_key:
        logger.warning("daily-podcast x: XAI_API_KEY not set; skipping")
        return []

    limit = int(source.extra.get("limit", 15))
    lang = (source.extra.get("lang") or "ja").strip()
    model = (source.extra.get("model") or os.environ.get("XAI_MODEL") or DEFAULT_MODEL).strip()

    prompt = _build_prompt(query=query, limit=limit, lang=lang)
    payload: dict[str, Any] = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "search_parameters": {
            "mode": "on",
            "sources": [{"type": "x"}],
        },
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }

    try:
        resp = http.post_json(
            XAI_CHAT_URL, json=payload, headers=headers, timeout=60
        )
    except http.HttpError as exc:
        logger.warning("daily-podcast x '%s': %s", query, exc)
        return []

    content = _extract_assistant_content(resp)
    posts = _parse_first_json_array(content)
    if posts is None:
        logger.warning(
            "daily-podcast x '%s': could not parse JSON array from response", query
        )
        return []

    out: list[dict[str, Any]] = []
    for post in posts[:limit]:
        if not isinstance(post, dict):
            continue
        body = (post.get("body") or post.get("text") or "").strip()
        url = (post.get("url") or "").strip()
        if not url:
            continue
        title = (post.get("title") or body[:80]).strip()
        if not title:
            continue
        out.append(
            {
                "url": url,
                "title": title,
                "summary": truncate(body, 500),
                "points": _coerce_int(post.get("likes") or post.get("like_count")),
                "comments": _coerce_int(post.get("replies") or post.get("reply_count")),
                "published_at": normalize_ts(
                    post.get("created_at") or post.get("date")
                ),
                "language_hint": lang,
                "author": post.get("author") or post.get("handle"),
            }
        )
    return out


def _build_prompt(*, query: str, limit: int, lang: str) -> str:
    return (
        f"Search X (formerly Twitter) for the top {limit} posts about: {query}\n"
        f"Prefer posts in language '{lang}' when available.\n\n"
        "Return ONLY a JSON array (no prose, no markdown fences). Each element "
        "must be an object with exactly these keys:\n"
        '  - "title": first 80 characters of the post text\n'
        '  - "url": the canonical post URL (https://x.com/<handle>/status/<id>)\n'
        '  - "body": full post text\n'
        '  - "author": "@handle" of the author\n'
        '  - "created_at": ISO 8601 timestamp (UTC)\n'
        '  - "likes": integer like count, 0 if unknown\n'
        '  - "replies": integer reply count, 0 if unknown\n'
    )


def _extract_assistant_content(resp: dict[str, Any]) -> str:
    if not isinstance(resp, dict):
        return ""
    choices = resp.get("choices") or []
    if not choices:
        return ""
    first = choices[0] or {}
    message = first.get("message") or {}
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        # OpenAI-style list of content parts; concatenate text fragments.
        return "".join(
            part.get("text", "")
            for part in content
            if isinstance(part, dict) and part.get("type") == "text"
        )
    return ""


_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.MULTILINE)


def _parse_first_json_array(content: str) -> list[Any] | None:
    if not content:
        return None
    text = _FENCE_RE.sub("", content).strip()
    start = text.find("[")
    end = text.rfind("]")
    if start < 0 or end <= start:
        return None
    try:
        parsed = json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, list) else None


def _coerce_int(v: Any) -> int | None:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None
