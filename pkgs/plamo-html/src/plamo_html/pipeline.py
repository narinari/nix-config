"""翻訳パイプライン: スキップ判定 -> キャッシュ -> 翻訳 -> 検証 -> 再試行。"""

from __future__ import annotations

import enum
from collections import Counter
from dataclasses import dataclass
from typing import Callable, Mapping, Sequence

from plamo_html.cache import TranslationCache, make_key
from plamo_html.client import TranslationClient, max_tokens_for
from plamo_html.errors import ServerError
from plamo_html.inline import restore
from plamo_html.model import Item, Protected, Unit, UnitKind
from plamo_html.prompt import Form, GlossaryEntry, Pair, build_prompt
from plamo_html.skip import SkipKind, classify
from plamo_html.validate import Invalid, Valid, check_translation


class Outcome(enum.Enum):
    TRANSLATED = "translated"
    CACHED = "cached"
    SKIPPED_JAPANESE = "skipped_japanese"
    SKIPPED_OTHER = "skipped_other"
    FAILED = "failed"


@dataclass(frozen=True)
class Settings:
    context: str
    form: Form
    glossary: tuple[GlossaryEntry, ...]
    history_chars: int


@dataclass(frozen=True)
class History:
    limit: int
    pairs: tuple[Pair, ...] = ()

    def push(self, pair: Pair) -> History:
        pairs = self.pairs + (pair,)
        while pairs and sum(len(p.src) + len(p.dst) for p in pairs) > self.limit:
            pairs = pairs[1:]
        return History(self.limit, pairs)

    def cleared(self) -> History:
        return History(self.limit)


@dataclass(frozen=True)
class Failure:
    index: int
    kind: UnitKind
    source: str
    reason: str
    last_output: str | None


@dataclass(frozen=True)
class Stats:
    total: int
    translated: int
    cached: int
    skipped_japanese: int
    skipped_other: int
    failed: int


@dataclass(frozen=True)
class RunResult:
    restored: Mapping[int, tuple[Item, ...]]
    stats: Stats
    failures: tuple[Failure, ...]


ProgressFn = Callable[[int, int], None]


def _attempt(
    client: TranslationClient, settings: Settings, history: History, p: Protected
) -> tuple[Valid, str] | Invalid:
    prompt = build_prompt(
        context=settings.context,
        history=history.pairs,
        glossary=settings.glossary,
        src=p.text,
        form=settings.form,
    )
    try:
        output = client.complete(prompt, max_tokens_for(p.text))
    except ServerError as e:
        return Invalid(f"server error: {e}")
    result = check_translation(p, output)
    return (result, output.strip()) if isinstance(result, Valid) else result


def _translate(
    client: TranslationClient, settings: Settings, history: History, p: Protected
) -> tuple[Valid, str] | Invalid:
    first = _attempt(client, settings, history, p)
    if isinstance(first, tuple) or not history.pairs:
        return first
    return _attempt(client, settings, history.cleared(), p)


def _stats(total: int, counts: Counter[Outcome]) -> Stats:
    return Stats(
        total=total,
        translated=counts[Outcome.TRANSLATED],
        cached=counts[Outcome.CACHED],
        skipped_japanese=counts[Outcome.SKIPPED_JAPANESE],
        skipped_other=counts[Outcome.SKIPPED_OTHER],
        failed=counts[Outcome.FAILED],
    )


def run_pipeline(
    units: Sequence[Unit],
    client: TranslationClient,
    cache: TranslationCache,
    settings: Settings,
    progress: ProgressFn | None = None,
) -> RunResult:
    """ServerUnreachable は握りつぶさず呼び出し側に伝播させる。"""
    counts: Counter[Outcome] = Counter()
    restored: dict[int, tuple[Item, ...]] = {}
    failures: list[Failure] = []
    history = History(settings.history_chars)
    for done, unit in enumerate(units, 1):
        p = unit.protected
        skip = classify(p)
        if skip is not None:
            counts[
                Outcome.SKIPPED_JAPANESE if skip.kind is SkipKind.JAPANESE else Outcome.SKIPPED_OTHER
            ] += 1
        else:
            key = make_key(settings.context, settings.form, settings.glossary, p.text)
            cached = _from_cache(cache.get(key), p)
            if cached is not None:
                outcome, valid, dst = Outcome.CACHED, cached[0], cached[1]
            else:
                result = _translate(client, settings, history, p)
                if isinstance(result, Invalid):
                    counts[Outcome.FAILED] += 1
                    failures.append(Failure(unit.index, unit.kind, p.text, result.reason, result.output))
                    _tick(progress, done, len(units))
                    continue
                outcome, (valid, dst) = Outcome.TRANSLATED, result
                cache.put(key, dst)
            counts[outcome] += 1
            restored[unit.index] = restore(p, valid.tokens)
            history = history.push(Pair(p.text, dst))
        _tick(progress, done, len(units))
    return RunResult(restored, _stats(len(units), counts), tuple(failures))


def _from_cache(value: str | None, p: Protected) -> tuple[Valid, str] | None:
    if value is None:
        return None
    checked = check_translation(p, value)
    return (checked, value) if isinstance(checked, Valid) else None


PROGRESS_EVERY = 10


def _tick(progress: ProgressFn | None, done: int, total: int) -> None:
    if progress is not None and (done % PROGRESS_EVERY == 0 or done == total):
        progress(done, total)
