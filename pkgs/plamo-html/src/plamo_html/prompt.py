"""PFML3 プロンプト組み立て。改行は入れず全て連結する。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Sequence

Form = Literal["plain", "polite"]


@dataclass(frozen=True)
class Pair:
    src: str
    dst: str


@dataclass(frozen=True)
class GlossaryEntry:
    source: str
    target: str


_INPUT = "<|plamo:tag|>input<|plamo:key|>lang<|plamo:val|>en<|plamo:msg|>"
_OUTPUT = "<|plamo:tag|>output<|plamo:key|>lang<|plamo:val|>ja"


def build_prompt(
    *,
    context: str,
    history: Sequence[Pair],
    glossary: Sequence[GlossaryEntry],
    src: str,
    form: Form,
) -> str:
    parts = [
        "<|plamo:tag|>dataset<|plamo:msg|>translation",
        f"<|plamo:tag|>context<|plamo:msg|>{context}",
    ]
    for pair in history:
        parts.append(f"{_INPUT}{pair.src}{_OUTPUT}<|plamo:msg|>{pair.dst}")
    if glossary:
        parts.append("<|plamo:tag|>glossary")
        parts.extend(f"<|plamo:index|>{g.source}<|plamo:item|>{g.target}" for g in glossary)
    parts.append(f"{_INPUT}{src}{_OUTPUT}<|plamo:key|>form<|plamo:val|>{form}<|plamo:msg|>")
    return "".join(parts)
