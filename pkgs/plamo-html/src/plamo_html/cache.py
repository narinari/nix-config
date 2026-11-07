"""追記型 JSONL キャッシュ。1 件ごとに flush するので途中停止から再開できる。"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Protocol, Sequence

from plamo_html.model import CacheKey
from plamo_html.prompt import GlossaryEntry


class TranslationCache(Protocol):
    def get(self, key: CacheKey) -> str | None: ...

    def put(self, key: CacheKey, value: str) -> None: ...


def default_cache_path() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "plamo-translate" / "html" / "cache.jsonl"


def make_key(context: str, form: str, glossary: Sequence[GlossaryEntry], src: str) -> CacheKey:
    payload = json.dumps(
        [context, form, [[g.source, g.target] for g in glossary], src],
        ensure_ascii=False,
    )
    return CacheKey(hashlib.sha256(payload.encode("utf-8")).hexdigest())


class NullCache:
    """--no-cache: 読み書きとも行わない。"""

    def get(self, key: CacheKey) -> str | None:
        return None

    def put(self, key: CacheKey, value: str) -> None:
        return None


class FileCache:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._entries: dict[CacheKey, str] = {}
        self._load()

    def _load(self) -> None:
        if not self._path.exists():
            return
        with self._path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                self._ingest(line)

    def _ingest(self, line: str) -> None:
        # 途中停止で壊れた行は捨てる (その単位は再翻訳されるだけ)
        try:
            row = json.loads(line)
            key, value = row["k"], row["v"]
        except (ValueError, KeyError, TypeError):
            return
        if isinstance(key, str) and isinstance(value, str):
            self._entries[CacheKey(key)] = value

    def get(self, key: CacheKey) -> str | None:
        return self._entries.get(key)

    def put(self, key: CacheKey, value: str) -> None:
        self._entries[key] = value
        self._path.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps({"k": key, "v": value}, ensure_ascii=False) + "\n"
        needs_newline = self._path.exists() and not self._ends_with_newline()
        with self._path.open("a", encoding="utf-8") as f:
            if needs_newline:
                f.write("\n")
            f.write(line)
            f.flush()

    def _ends_with_newline(self) -> bool:
        if self._path.stat().st_size == 0:
            return True
        with self._path.open("rb") as r:
            r.seek(-1, os.SEEK_END)
            return r.read(1) == b"\n"
