"""Plugin configuration: env defaults and topics.toml loader.

`topics.toml` is the single source of truth for which topics get generated
and which sources feed them. It lives under `DAILY_PODCAST_STATE_DIR/topics.toml`
(default `/var/lib/hermes-podcast/topics.toml`) and is mutated by `add_topic`.

The schema is intentionally permissive: a topic is `{ slug, title,
description, voicevox_speaker_id?, target_segment_count?, sources: [...] }`,
where each source is `{ type, ... }`. Unknown keys are passed through so a
future source type can ship without a plugin rebuild.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

ENV_STATE_DIR = "DAILY_PODCAST_STATE_DIR"
ENV_VOICEVOX_URL = "DAILY_PODCAST_VOICEVOX_URL"
ENV_PUBLIC_BASE_URL = "DAILY_PODCAST_PUBLIC_BASE_URL"
ENV_DEFAULT_SPEAKER = "DAILY_PODCAST_DEFAULT_SPEAKER_ID"
ENV_AUTHOR = "DAILY_PODCAST_AUTHOR"
ENV_OWNER_EMAIL = "DAILY_PODCAST_OWNER_EMAIL"
ENV_LLM_MODEL = "HERMES_DAILY_PODCAST_LLM_MODEL"
ENV_SCORE_MODEL = "HERMES_DAILY_PODCAST_SCORE_MODEL"
ENV_SUMMARIZE_MODEL = "HERMES_DAILY_PODCAST_SUMMARIZE_MODEL"
ENV_LLM_BASE_URL = "HERMES_DAILY_PODCAST_LLM_BASE_URL"
ENV_LLM_API_KEY = "OPENAI_API_KEY"  # aperture との互換
ENV_ALLOW_POPULARITY_FALLBACK = "DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK"

DEFAULT_STATE_DIR = "/var/lib/hermes-podcast"
DEFAULT_VOICEVOX_URL = "http://127.0.0.1:50021"
# FQDN がデフォルト: 短い hostname だと Overcast 等が URL を validation 拒否し、
# また手動で write_feed を呼んだ際に env が無くても正しい URL を出す必要がある。
DEFAULT_PUBLIC_BASE_URL = "http://khali.taild10c60.ts.net/podcasts"
DEFAULT_SPEAKER_ID = 2  # 四国めたん ノーマル
DEFAULT_AUTHOR = "friday hermes"
DEFAULT_LLM_MODEL = "qwen3.6:35b-mlx"
# 採点 (HIGH/MID/LOW 分類) は短い文脈を一括で裁くだけなので 4-8B 帯で十分。
# qwen3.5:4b-mlx は hail-mary に pull 済み。summarize より 3-5 倍速い。
DEFAULT_SCORE_MODEL = "qwen3.5:4b-mlx"
DEFAULT_SUMMARIZE_MODEL = DEFAULT_LLM_MODEL
DEFAULT_LLM_BASE_URL = "http://ai/v1"  # aperture

DEFAULT_SEGMENT_COUNT = 5
DEFAULT_TIMEZONE = "Asia/Tokyo"


@dataclass(frozen=True)
class SourceConfig:
    type: str
    extra: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "SourceConfig":
        t = str(raw.get("type", "")).strip()
        if not t:
            raise ValueError("source missing 'type'")
        extra = {k: v for k, v in raw.items() if k != "type"}
        return cls(type=t, extra=extra)


@dataclass(frozen=True)
class TopicConfig:
    slug: str
    title: str
    description: str
    voicevox_speaker_id: int
    target_segment_count: int
    sources: tuple[SourceConfig, ...]

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> "TopicConfig":
        slug = str(raw.get("slug", "")).strip()
        if not slug:
            raise ValueError("topic missing 'slug'")
        sources_raw = raw.get("sources") or []
        if not isinstance(sources_raw, list):
            raise ValueError(f"topic {slug}: sources must be a list")
        sources = tuple(SourceConfig.from_dict(s) for s in sources_raw)
        return cls(
            slug=slug,
            title=str(raw.get("title") or slug),
            description=str(raw.get("description") or ""),
            voicevox_speaker_id=int(
                raw.get("voicevox_speaker_id") or _default_speaker_id()
            ),
            target_segment_count=int(
                raw.get("target_segment_count") or DEFAULT_SEGMENT_COUNT
            ),
            sources=sources,
        )


def _default_speaker_id() -> int:
    raw = os.environ.get(ENV_DEFAULT_SPEAKER, "").strip()
    if not raw:
        return DEFAULT_SPEAKER_ID
    try:
        return int(raw)
    except ValueError:
        logger.warning(
            "daily-podcast: invalid %s=%r; falling back to %d",
            ENV_DEFAULT_SPEAKER,
            raw,
            DEFAULT_SPEAKER_ID,
        )
        return DEFAULT_SPEAKER_ID


def state_dir() -> Path:
    return Path(os.environ.get(ENV_STATE_DIR, DEFAULT_STATE_DIR))


def topics_toml_path() -> Path:
    return state_dir() / "topics.toml"


def episodes_dir() -> Path:
    return state_dir() / "episodes"


def state_db_path() -> Path:
    return state_dir() / "state.sqlite"


def voicevox_url() -> str:
    return os.environ.get(ENV_VOICEVOX_URL, DEFAULT_VOICEVOX_URL).rstrip("/")


def public_base_url() -> str:
    return os.environ.get(ENV_PUBLIC_BASE_URL, DEFAULT_PUBLIC_BASE_URL).rstrip("/")


def author() -> str:
    return os.environ.get(ENV_AUTHOR, DEFAULT_AUTHOR).strip() or DEFAULT_AUTHOR


def owner_email() -> str:
    """Mailbox shown in <itunes:owner><itunes:email>. Apple requires presence
    but no incoming-mail capability — a synthesized address is fine."""
    explicit = os.environ.get(ENV_OWNER_EMAIL, "").strip()
    if explicit:
        return explicit
    from urllib.parse import urlparse

    host = urlparse(public_base_url()).hostname or "localhost"
    return f"podcast@{host}"


def llm_model() -> str:
    """Legacy single-model entrypoint. Returns summarize_model() for backward
    compatibility — older callers (and tests) expect "the model" to mean the
    heavy summarization model."""
    return summarize_model()


def score_model() -> str:
    """Lightweight model for batch scoring (HIGH/MID/LOW classification).

    Precedence: SCORE_MODEL env > LLM_MODEL env (legacy single-model) > default.
    """
    explicit = os.environ.get(ENV_SCORE_MODEL, "").strip()
    if explicit:
        return explicit
    legacy = os.environ.get(ENV_LLM_MODEL, "").strip()
    if legacy:
        return legacy
    return DEFAULT_SCORE_MODEL


def summarize_model() -> str:
    """Heavy model for per-article Japanese summarization / translation.

    Precedence: SUMMARIZE_MODEL env > LLM_MODEL env (legacy alias) > default.
    """
    explicit = os.environ.get(ENV_SUMMARIZE_MODEL, "").strip()
    if explicit:
        return explicit
    legacy = os.environ.get(ENV_LLM_MODEL, "").strip()
    if legacy:
        return legacy
    return DEFAULT_SUMMARIZE_MODEL


def llm_base_url() -> str:
    return os.environ.get(ENV_LLM_BASE_URL, DEFAULT_LLM_BASE_URL).rstrip("/")


def llm_api_key() -> str:
    return os.environ.get(ENV_LLM_API_KEY, "").strip()


def allow_popularity_fallback() -> bool:
    """Whether scoring may fall back to raw popularity when the LLM fails.

    Default False (fail closed): the popularity path cannot judge genre fit,
    and every episode it ever produced was full of off-topic articles.
    """
    raw = os.environ.get(ENV_ALLOW_POPULARITY_FALLBACK, "").strip().lower()
    return raw in {"1", "true", "yes", "on"}


def load_topics() -> list[TopicConfig]:
    """Parse topics.toml. Returns empty list if missing (not an error)."""
    path = topics_toml_path()
    if not path.exists():
        logger.info("daily-podcast: %s not found; no topics defined", path)
        return []

    raw = path.read_text(encoding="utf-8")
    try:
        import tomllib
    except ImportError:  # pragma: no cover - python < 3.11
        import tomli as tomllib  # type: ignore[import-not-found,no-redef]
    data = tomllib.loads(raw)

    topics_raw = data.get("topic") or []
    if not isinstance(topics_raw, list):
        raise ValueError("topics.toml: [[topic]] must be an array of tables")
    return [TopicConfig.from_dict(t) for t in topics_raw]


def find_topic(slug: str) -> TopicConfig | None:
    for t in load_topics():
        if t.slug == slug:
            return t
    return None


def append_topic_to_toml(new_topic: dict[str, Any]) -> None:
    """Atomically append a `[[topic]]` block to topics.toml.

    We rewrite the file rather than mutate to avoid TOML library round-trip
    issues with comments / formatting. The new block is appended verbatim.
    """
    import tempfile

    path = topics_toml_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = path.read_text(encoding="utf-8") if path.exists() else ""

    block = _topic_to_toml_block(new_topic)
    combined = existing.rstrip() + "\n\n" + block + "\n" if existing else block + "\n"

    fd, tmp = tempfile.mkstemp(prefix=".topics.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(combined)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _topic_to_toml_block(t: dict[str, Any]) -> str:
    """Render a topic dict as a [[topic]] + [[topic.sources]] block."""
    lines: list[str] = ["[[topic]]"]
    for key in ("slug", "title", "description"):
        if key in t:
            lines.append(f'{key} = {_toml_str(t[key])}')
    for key in ("voicevox_speaker_id", "target_segment_count"):
        if key in t and t[key] is not None:
            lines.append(f"{key} = {int(t[key])}")
    for src in t.get("sources") or []:
        lines.append("")
        lines.append("[[topic.sources]]")
        for k, v in src.items():
            if isinstance(v, str):
                lines.append(f"{k} = {_toml_str(v)}")
            elif isinstance(v, bool):
                lines.append(f"{k} = {'true' if v else 'false'}")
            elif isinstance(v, (int, float)):
                lines.append(f"{k} = {v}")
            elif isinstance(v, list):
                rendered = ", ".join(_toml_str(str(x)) for x in v)
                lines.append(f"{k} = [{rendered}]")
    return "\n".join(lines)


def _toml_str(s: str) -> str:
    """Render a Python string as a TOML basic string with safe escaping."""
    escaped = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'
