"""LLM-based importance scoring for candidates.

We send all candidates in one batch and ask the LLM to classify each into one
of three discrete labels (HIGH/MID/LOW), returning a JSON object
`{ "scores": [{"id": int, "label": "HIGH|MID|LOW", "reason": str}, ...] }`.

Doing it in one call (instead of N calls) is much faster and keeps relative
ordering calibrated — the LLM sees its peers. The discrete label space is
stabler than a 0-10 float (the model used to waver between 3/4/5 for similar
candidates); we map labels back to a numeric score internally so the existing
`MIN_SELECTION_SCORE` floor and `select_top` ranking keep working.

The scoring pass is intentionally cheap: it runs against `cfg.score_model()`
(default `qwen3.5:4b-mlx` on hail-mary) so we can throw 30-60 candidates at it
without monopolizing the heavy summarization model.
"""

from __future__ import annotations

import logging
from typing import Any

from . import config as cfg
from . import llm

logger = logging.getLogger(__name__)

# Discrete label → numeric score. Anchored so HIGH/MID stay above the
# MIN_SELECTION_SCORE floor and LOW (plus "off-topic", which the prompt maps
# to LOW) sinks below it.
LABEL_TO_SCORE: dict[str, float] = {
    "HIGH": 10.0,
    "MID": 5.0,
    "LOW": 1.0,
}

MIN_SELECTION_SCORE = 3.0

# opt-in フォールバック時の鮮度減衰: ブクマ数は単調増加なので、鮮度を見ないと
# 古い高ブクマ記事が恒久的に上位を占める。
FALLBACK_HALF_LIFE_DAYS = 7
FALLBACK_MAX_AGE_DAYS = 14


class ScoreUnavailableError(RuntimeError):
    """Raised when LLM scoring failed and popularity fallback is disabled.

    Fail closed: an episode assembled without genre judgement is worse than
    no episode (every fallback-built episode shipped off-topic articles).
    """


def score_candidates(
    candidates: list[dict[str, Any]],
    *,
    topic: cfg.TopicConfig,
    hint: str | None = None,
    recent_titles: list[str] | None = None,
) -> list[dict[str, Any]]:
    """Return candidates with `score` and `score_reason` keys filled in.

    Candidates that the LLM couldn't score keep score=0.0 so they sink to the
    bottom of the ranking but aren't lost.

    `recent_titles` are titles already adopted in recent episodes — passed to
    the prompt so the model marks effectively-identical stories LOW.
    """
    if not candidates:
        return []

    indexed = [{**c, "_id": i} for i, c in enumerate(candidates)]

    user_msg = _build_prompt(topic, indexed, hint, recent_titles)
    messages = [
        {
            "role": "system",
            "content": (
                "あなたは特定ジャンルの番組プロデューサー兼編集者です。"
                "「番組のジャンル」に直接該当しない候補は LOW を付け、決して採用しないでください。"
                "人気記事だからといって HIGH を付けるのは禁止です — ジャンル一致度が最優先です。"
                "出力は厳密な JSON のみ、自然言語の前置きや markdown のコードブロックは禁止です。"
            ),
        },
        {"role": "user", "content": user_msg},
    ]

    try:
        result = llm.chat_json(
            messages,
            model=cfg.score_model(),
            temperature=0.1,
            # thinking がコンテンツ/トークン枠を食い潰して空応答になる事故が
            # あったため、採点パスでは思考を切り、枠にも余裕を持たせる。
            max_tokens=8192,
            disable_thinking=True,
        )
    except llm.LlmError as exc:
        return _handle_scoring_failure(candidates, f"LLM call failed: {exc}")

    scores_raw = result.get("scores") if isinstance(result, dict) else None
    if not isinstance(scores_raw, list):
        return _handle_scoring_failure(
            candidates,
            f"LLM returned bad shape (no 'scores' list): {result!r:.300}",
        )

    score_by_id: dict[int, dict[str, Any]] = {}
    for s in scores_raw:
        if not isinstance(s, dict):
            continue
        try:
            cid = int(s.get("id"))
        except (TypeError, ValueError):
            continue
        score_by_id[cid] = _decide_score(s)

    out: list[dict[str, Any]] = []
    for i, c in enumerate(candidates):
        decided = score_by_id.get(i, {"score": 0.0, "score_reason": ""})
        out.append({**c, **decided})
    return out


def _handle_scoring_failure(
    candidates: list[dict[str, Any]], reason: str
) -> list[dict[str, Any]]:
    """Fail closed by default; popularity fallback only when opted in via
    DAILY_PODCAST_ALLOW_POPULARITY_FALLBACK."""
    if cfg.allow_popularity_fallback():
        logger.error(
            "daily-podcast score: %s; FALLING BACK TO POPULARITY (opt-in)",
            reason,
        )
        return _fallback_score(candidates)
    logger.error(
        "daily-podcast score: %s; refusing to build an episode without "
        "genre judgement (set %s=1 to allow popularity fallback)",
        reason,
        cfg.ENV_ALLOW_POPULARITY_FALLBACK,
    )
    raise ScoreUnavailableError(reason)


def _decide_score(s: dict[str, Any]) -> dict[str, Any]:
    """Convert one LLM verdict (label + reason) into the internal numeric form.

    Backward compatible: if the model emits the legacy `score` float instead
    of `label`, we still accept it. New code path is label-first.
    """
    reason = str(s.get("reason") or "")[:300]

    label_raw = s.get("label")
    if isinstance(label_raw, str):
        label = label_raw.strip().upper()
        if label in LABEL_TO_SCORE:
            return {"score": LABEL_TO_SCORE[label], "score_reason": reason}

    # Legacy / fallback path: numeric score directly.
    if "score" in s:
        try:
            sv = float(s.get("score"))
        except (TypeError, ValueError):
            sv = 0.0
        return {
            "score": max(0.0, min(10.0, sv)),
            "score_reason": reason,
        }

    return {"score": 0.0, "score_reason": reason}


def _build_prompt(
    topic: cfg.TopicConfig,
    indexed: list[dict[str, Any]],
    hint: str | None,
    recent_titles: list[str] | None = None,
) -> str:
    lines: list[str] = []
    lines.append(f"## 番組のジャンル\n{topic.title}\n\n{topic.description}\n")
    if hint:
        lines.append(f"## 今日の観点\n{hint}\n")
    if recent_titles:
        titles = "\n".join(f"- {t}" for t in recent_titles[:30])
        lines.append(
            "## 直近のエピソードで扱った既出タイトル\n"
            f"{titles}\n"
            "これらと同一・実質同内容の候補は LOW を付けること。\n"
        )
    lines.append(
        "## 採点ラベル (HIGH / MID / LOW)\n"
        "- HIGH: 番組のジャンルに直接該当し、内容が濃く実用的・新規性が高い\n"
        "- MID: 番組のジャンルに該当するが、内容が浅い or 既出寄り\n"
        "- LOW: ジャンル外 / ノイズ (宣伝・スパム・釣り) / 重複 / 中身が薄い\n"
        "\n"
        "## 採点ルール\n"
        "- **ジャンル一致が最優先**。番組のジャンルに直接該当しない候補は問答無用で LOW。\n"
        "  たとえばホビー模型ジャンルでサッカー / 政治 / 芸能 / 一般 IT ニュースが出てきたら全部 LOW。\n"
        "- 人気が高くてもジャンル外なら LOW。スコアを甘くしない。\n"
        "- 同じ話題で別ソースの重複候補は、最良の 1 つを HIGH / MID、残りを LOW にする。\n"
        "- 迷ったら MID ではなく LOW を選ぶ。LOW は最終選定で必ず除外される。\n"
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
        '{"scores": [{"id": <int>, "label": "HIGH"|"MID"|"LOW", '
        '"reason": "<日本語1文>"}, ...]}'
    )
    return "\n".join(lines)


def _fallback_score(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Opt-in fallback: rank by points, decayed by staleness.

    Bookmark counts only ever grow, so without decay the same old viral
    articles win every night. Candidates without published_at keep full
    score — we can't tell their age, and sinking them would empty sparse
    topics.
    """
    out: list[dict[str, Any]] = []
    for c in candidates:
        pts = c.get("points") or 0
        try:
            pts = int(pts)
        except (TypeError, ValueError):
            pts = 0
        score = min(10.0, pts / 50.0)
        age_days = _age_days(c.get("published_at"))
        reason = "fallback: points-based"
        if age_days is not None:
            if age_days > FALLBACK_MAX_AGE_DAYS:
                score = 0.0
                reason = f"fallback: stale ({age_days}d)"
            elif age_days > FALLBACK_HALF_LIFE_DAYS:
                score /= 2
                reason = f"fallback: points halved ({age_days}d)"
        out.append({**c, "score": score, "score_reason": reason})
    return out


def _age_days(published_at: Any) -> int | None:
    if not published_at:
        return None
    from datetime import datetime, timezone

    try:
        ts = datetime.fromisoformat(str(published_at).replace("Z", "+00:00"))
    except ValueError:
        return None
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - ts).days


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
