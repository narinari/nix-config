"""LLM-based importance scoring for candidates.

We send all candidates in one batch and ask the LLM to return a JSON object
`{ "scores": [{"id": int, "score": float, "reason": str}, ...] }`. Doing it
in one call (instead of N calls) is much faster and keeps relative ordering
calibrated — the LLM sees its peers.
"""

from __future__ import annotations

import logging
from typing import Any

from . import config as cfg
from . import llm

logger = logging.getLogger(__name__)


def score_candidates(
    candidates: list[dict[str, Any]],
    *,
    topic: cfg.TopicConfig,
    hint: str | None = None,
) -> list[dict[str, Any]]:
    """Return candidates with `score` and `score_reason` keys filled in.

    Candidates that the LLM couldn't score keep score=0.0 so they sink to the
    bottom of the ranking but aren't lost.
    """
    if not candidates:
        return []

    indexed = [{**c, "_id": i} for i, c in enumerate(candidates)]

    user_msg = _build_prompt(topic, indexed, hint)
    messages = [
        {
            "role": "system",
            "content": (
                "あなたは特定ジャンルの番組プロデューサー兼編集者です。"
                "「番組のジャンル」に直接該当しない候補は score=0 を付け、決して採用しないでください。"
                "人気記事だからといって score を上げるのは禁止です — ジャンル一致度が最優先です。"
                "出力は厳密な JSON のみ、自然言語の前置きや markdown のコードブロックは禁止です。"
            ),
        },
        {"role": "user", "content": user_msg},
    ]

    try:
        result = llm.chat_json(messages, temperature=0.1, max_tokens=4096)
    except llm.LlmError as exc:
        # Make the failure mode obvious in logs — silently falling back to
        # popularity ranking gives wrong-but-plausible episodes (sports / news
        # instead of the requested hobby topic).
        logger.error(
            "daily-podcast score: LLM call failed (%s); FALLING BACK TO POPULARITY",
            exc,
        )
        return _fallback_score(candidates)

    scores_raw = result.get("scores") if isinstance(result, dict) else None
    if not isinstance(scores_raw, list):
        logger.error(
            "daily-podcast score: LLM returned bad shape (no 'scores' list); "
            "FALLING BACK TO POPULARITY. got=%r",
            result,
        )
        return _fallback_score(candidates)

    score_by_id: dict[int, dict[str, Any]] = {}
    for s in scores_raw:
        if not isinstance(s, dict):
            continue
        try:
            cid = int(s.get("id"))
            sv = float(s.get("score"))
        except (TypeError, ValueError):
            continue
        score_by_id[cid] = {
            "score": max(0.0, min(10.0, sv)),
            "score_reason": str(s.get("reason") or "")[:300],
        }

    out: list[dict[str, Any]] = []
    for i, c in enumerate(candidates):
        decided = score_by_id.get(i, {"score": 0.0, "score_reason": ""})
        out.append({**c, **decided})
    return out


def _build_prompt(
    topic: cfg.TopicConfig,
    indexed: list[dict[str, Any]],
    hint: str | None,
) -> str:
    lines: list[str] = []
    lines.append(f"## 番組のジャンル\n{topic.title}\n\n{topic.description}\n")
    if hint:
        lines.append(f"## 今日の観点\n{hint}\n")
    lines.append(
        "## 採点基準 (0-10)\n"
        "- **ジャンル一致が最優先**。番組のジャンルに直接該当しない候補は問答無用で score=0。\n"
        "  たとえばホビー模型ジャンルでサッカー / 政治 / 芸能 / 一般 IT ニュースが出てきたら全部 0。\n"
        "- ジャンルに一致した上で: 実用に近いか / 深掘り価値があるか / 新規性\n"
        "- ノイズ (宣伝・スパム・釣り) は score=0\n"
        "- 重複候補 (同じ話題で別ソース) はどちらか 1 つを高くつけ、他は 0\n"
    )
    lines.append("## 候補\n")
    for c in indexed:
        lines.append(
            f"- id={c['_id']} src={c.get('source')} pts={c.get('points')} "
            f"comments={c.get('comments')}\n"
            f"  title: {c.get('title','')[:200]}\n"
            f"  url: {c.get('url','')}\n"
            f"  snippet: {(c.get('summary') or '')[:300]}"
        )
    lines.append(
        "\n## 出力 (JSON のみ)\n"
        '{"scores": [{"id": <int>, "score": <0-10 float>, "reason": "<日本語1文>"}, ...]}'
    )
    return "\n".join(lines)


def _fallback_score(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Fallback: rank by points-ish signal if LLM unavailable."""
    out: list[dict[str, Any]] = []
    for c in candidates:
        pts = c.get("points") or 0
        try:
            pts = int(pts)
        except (TypeError, ValueError):
            pts = 0
        # Map roughly to 0..10 via log-ish scaling.
        score = min(10.0, pts / 50.0)
        out.append({**c, "score": score, "score_reason": "fallback: points-based"})
    return out


MIN_SELECTION_SCORE = 3.0


def select_top(
    scored: list[dict[str, Any]],
    target: int,
) -> list[dict[str, Any]]:
    """Pick up to `target` items, but never include score < MIN_SELECTION_SCORE.

    Without the floor, a fully off-topic batch (e.g. only sports articles for a
    hobby-models topic) still produced an "episode" full of trash. With the
    floor we'd rather ship a short / empty episode than a confidently wrong one.
    """
    eligible = [c for c in scored if (c.get("score") or 0) >= MIN_SELECTION_SCORE]
    sorted_items = sorted(eligible, key=lambda c: c.get("score") or 0, reverse=True)
    return sorted_items[: max(1, target)]
