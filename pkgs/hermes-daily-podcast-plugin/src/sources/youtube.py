"""YouTube fetcher via ``yt-dlp``.

Uses ``yt-dlp ytsearch{N}:{query} --dump-json --skip-download`` to pull
search-result metadata without downloading anything. The plugin's Nix
package wires ``pkgs.yt-dlp`` into ``PATH``; if the binary is missing the
fetcher logs a warning and returns ``[]`` so the rest of the pipeline
keeps running.

We deliberately stop at metadata (title, description, view/like counts,
upload date) and *do not* pull captions. Transcript extraction is
expensive, frequently fails for auto-generated captions, and the LLM
summarizer downstream re-fetches richer context from the article URL
anyway.
"""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
from datetime import datetime, timezone
from typing import Any

from . import register
from .. import config as cfg
from ._common import truncate

logger = logging.getLogger(__name__)

YT_DLP_BIN = "yt-dlp"
DEFAULT_TIMEOUT_SECONDS = 180


@register("youtube")
def fetch(source: cfg.SourceConfig) -> list[dict[str, Any]]:
    query = (source.extra.get("query") or "").strip()
    if not query:
        logger.warning("daily-podcast youtube: source missing 'query'")
        return []
    limit = int(source.extra.get("limit", 10))
    lang = (source.extra.get("lang") or "ja").strip()
    timeout = int(source.extra.get("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))

    if not shutil.which(YT_DLP_BIN):
        logger.warning(
            "daily-podcast youtube: '%s' not on PATH; skipping (check that the "
            "Nix package propagates yt-dlp)",
            YT_DLP_BIN,
        )
        return []

    cmd = [
        YT_DLP_BIN,
        f"ytsearch{limit}:{query}",
        "--dump-json",
        "--skip-download",
        "--no-playlist",
        "--no-warnings",
        "--quiet",
        "--default-search",
        "ytsearch",
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        logger.warning(
            "daily-podcast youtube '%s': yt-dlp timed out after %ds",
            query,
            timeout,
        )
        return []
    except (FileNotFoundError, OSError) as exc:
        logger.warning("daily-podcast youtube '%s': yt-dlp invocation failed: %s", query, exc)
        return []

    if result.returncode != 0:
        stderr_snippet = (result.stderr or "").strip().splitlines()
        stderr_msg = stderr_snippet[-1] if stderr_snippet else "(no stderr)"
        logger.warning(
            "daily-podcast youtube '%s': yt-dlp exited %d: %s",
            query,
            result.returncode,
            stderr_msg,
        )

    out: list[dict[str, Any]] = []
    for line in (result.stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            video = json.loads(line)
        except json.JSONDecodeError:
            continue
        title = (video.get("title") or "").strip()
        url = video.get("webpage_url") or video.get("original_url")
        if not title or not url:
            continue
        out.append(
            {
                "url": url,
                "title": title,
                "summary": truncate(video.get("description") or "", 500),
                "points": _coerce_int(video.get("view_count")),
                "comments": _coerce_int(video.get("like_count")),
                "published_at": _yt_upload_date_to_iso(video.get("upload_date")),
                "language_hint": lang,
                "channel": video.get("channel") or video.get("uploader"),
                "duration_sec": _coerce_int(video.get("duration")),
            }
        )
    return out


def _yt_upload_date_to_iso(s: Any) -> str | None:
    if not s or not isinstance(s, str) or len(s) != 8:
        return None
    try:
        return (
            datetime.strptime(s, "%Y%m%d")
            .replace(tzinfo=timezone.utc)
            .isoformat()
        )
    except ValueError:
        return None


def _coerce_int(v: Any) -> int | None:
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None
