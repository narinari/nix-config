"""--glossary の JSON を境界でパースする。"""

from __future__ import annotations

import json
from pathlib import Path

from plamo_html.errors import InputError
from plamo_html.prompt import GlossaryEntry

_FORMAT_HINT = 'expected JSON like [{"source": "...", "target": "..."}]'


def parse_glossary(raw: str, origin: str = "glossary") -> tuple[GlossaryEntry, ...]:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise InputError(f"{origin}: invalid JSON ({e}); {_FORMAT_HINT}") from e
    if not isinstance(data, list):
        raise InputError(f"{origin}: top level must be a list; {_FORMAT_HINT}")
    entries: list[GlossaryEntry] = []
    for i, row in enumerate(data):
        if not isinstance(row, dict):
            raise InputError(f"{origin}: entry #{i} is not an object; {_FORMAT_HINT}")
        source, target = row.get("source"), row.get("target")
        if not (isinstance(source, str) and source and isinstance(target, str) and target):
            raise InputError(f"{origin}: entry #{i} needs non-empty string source/target")
        entries.append(GlossaryEntry(source, target))
    return tuple(entries)


def load_glossary(path: Path) -> tuple[GlossaryEntry, ...]:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as e:
        raise InputError(f"cannot read glossary {path}: {e}") from e
    return parse_glossary(raw, str(path))
