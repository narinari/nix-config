"""Per-candidate summarization + translation to Japanese.

Single prompt does both jobs: the LLM gets the candidate metadata plus the
extracted body text and returns a short Japanese summary plus a short
"listener takeaway". For non-Japanese sources we ask explicitly for translation.
"""

from __future__ import annotations

import logging
from typing import Any

from . import config as cfg
from . import extract
from . import llm

logger = logging.getLogger(__name__)


def summarize_each(
    selected: list[dict[str, Any]],
    *,
    topic: cfg.TopicConfig,
    hint: str | None = None,
) -> list[dict[str, Any]]:
    """Return selected items enriched with `summary_ja` and `takeaway_ja`."""
    out: list[dict[str, Any]] = []
    for c in selected:
        body = extract.extract(c.get("url") or "")
        try:
            result = _ask_llm(c, body, topic, hint)
        except llm.LlmError:
            logger.exception("daily-podcast summarize: LLM failed for %s", c.get("url"))
            result = {
                "summary_ja": (c.get("summary") or c.get("title") or "")[:300],
                "takeaway_ja": "",
            }
        out.append({**c, **result})
    return out


def _ask_llm(
    candidate: dict[str, Any],
    body: str,
    topic: cfg.TopicConfig,
    hint: str | None,
) -> dict[str, Any]:
    src_lang = candidate.get("language_hint") or "und"
    translate_clause = (
        "本文は英語または日本語以外の言語の可能性があります。出力は必ず自然な日本語にしてください。"
        if src_lang != "ja"
        else "原文も出力も日本語です。"
    )

    user = (
        f"## トピック\n{topic.title}\n\n"
        f"## 観点\n{hint or '（標準観点で）'}\n\n"
        f"## 記事メタ\n"
        f"- title: {candidate.get('title','')}\n"
        f"- url: {candidate.get('url','')}\n"
        f"- source: {candidate.get('source','')}\n"
        f"- score_reason: {candidate.get('score_reason','')}\n\n"
        f"## 候補本文 (一部)\n{body or candidate.get('summary') or '(本文取得失敗)'}\n\n"
        f"{translate_clause}\n\n"
        "次の JSON 形式で返してください。前置き禁止。\n"
        '{"summary_ja": "<150〜250 字、です・ます調>", '
        '"takeaway_ja": "<聞き手向けの結論 1 文、80字以内>"}'
    )
    messages = [
        {
            "role": "system",
            "content": (
                "あなたは技術系ポッドキャストの構成作家です。"
                "事実を正確に、宣伝色を排し、誇張なしで日本語要約を書きます。"
            ),
        },
        {"role": "user", "content": user},
    ]
    return llm.chat_json(messages, temperature=0.3, max_tokens=600)
