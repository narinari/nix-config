"""dry-run / サマリ / 失敗レポートの整形。"""

from __future__ import annotations

import json
from collections import Counter
from typing import Sequence

from plamo_html.model import Unit
from plamo_html.pipeline import Failure, Stats
from plamo_html.skip import classify, latin_char_count


def dry_run_text(units: Sequence[Unit]) -> str:
    by_kind = Counter(u.kind.value for u in units)
    to_translate = [u for u in units if classify(u.protected) is None]
    english_chars = sum(latin_char_count(u.protected) for u in to_translate)
    lines = [f"blocks: {len(units)}"]
    lines += [f"  {kind}: {n}" for kind, n in sorted(by_kind.items())]
    lines.append(f"to translate: {len(to_translate)}")
    lines.append(f"skipped: {len(units) - len(to_translate)}")
    lines.append(f"english chars (to translate): {english_chars}")
    return "\n".join(lines)


def summary_text(stats: Stats) -> str:
    return (
        f"total={stats.total} translated={stats.translated} cached={stats.cached} "
        f"skipped_japanese={stats.skipped_japanese} skipped_other={stats.skipped_other} "
        f"failed={stats.failed}"
    )


def failures_json(failures: Sequence[Failure]) -> str:
    rows = [
        {
            "index": f.index,
            "kind": f.kind.value,
            "source": f.source,
            "reason": f.reason,
            "last_output": f.last_output,
        }
        for f in failures
    ]
    return json.dumps(rows, ensure_ascii=False, indent=2)
