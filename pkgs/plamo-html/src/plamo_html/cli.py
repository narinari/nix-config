"""plamo-html コマンド。"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn, Sequence

import lxml.html
from lxml import etree

from plamo_html.apply import apply_translations
from plamo_html.cache import FileCache, NullCache, TranslationCache, default_cache_path
from plamo_html.client import HttpClient, TranslationClient
from plamo_html.errors import InputError, ServerUnreachable
from plamo_html.extract import extract_units
from plamo_html.glossary import load_glossary
from plamo_html.pipeline import Settings, run_pipeline
from plamo_html.prompt import Form, GlossaryEntry
from plamo_html.report import dry_run_text, failures_json, summary_text

DEFAULT_URL = "http://127.0.0.1:8000"
DEFAULT_CONTEXT = "A technical document. Citations, code, file paths and URLs stay as-is."
DEFAULT_HISTORY_CHARS = 2000
EXIT_OK, EXIT_INPUT_ERROR, EXIT_UNREACHABLE = 0, 1, 2


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        # argparse 既定の終了コード 2 は「サーバー接続不可」と衝突するので 1 にする
        self.print_usage(sys.stderr)
        self.exit(EXIT_INPUT_ERROR, f"{self.prog}: error: {message}\n")


@dataclass(frozen=True)
class Options:
    input: Path
    output: Path
    url: str
    form: Form
    context: str
    glossary: tuple[GlossaryEntry, ...]
    history_chars: int
    dry_run: bool
    no_cache: bool
    report: Path | None


def _build_parser() -> argparse.ArgumentParser:
    p = _Parser(prog="plamo-html", description="Translate English HTML to Japanese with PLaMo 3.")
    p.add_argument("input", type=Path, metavar="INPUT.html")
    p.add_argument("-o", "--output", type=Path, help="output path (default: <stem>.ja.html)")
    p.add_argument("--url", help=f"llama-server URL (default: $PLAMO_URL or {DEFAULT_URL})")
    p.add_argument("--form", choices=("plain", "polite"), default="plain")
    p.add_argument("--context", default=DEFAULT_CONTEXT)
    p.add_argument("--glossary", type=Path, metavar="FILE", help='JSON [{"source","target"}]')
    p.add_argument("--history-chars", type=int, default=DEFAULT_HISTORY_CHARS, metavar="N")
    p.add_argument("--dry-run", action="store_true", help="count blocks only; do not call the LLM")
    p.add_argument("--no-cache", action="store_true", help="disable cache reads and writes")
    p.add_argument("--report", type=Path, metavar="PATH", help="write failed blocks as JSON")
    return p


def parse_options(argv: Sequence[str] | None) -> Options:
    ns = _build_parser().parse_args(argv)
    if ns.history_chars < 0:
        raise InputError("--history-chars must be >= 0")
    output = ns.output or ns.input.with_name(f"{ns.input.stem}.ja.html")
    if output.resolve() == ns.input.resolve():
        raise InputError(f"output path must differ from input: {output}")
    glossary = load_glossary(ns.glossary) if ns.glossary else ()
    return Options(
        input=ns.input,
        output=output,
        url=ns.url or os.environ.get("PLAMO_URL") or DEFAULT_URL,
        form=ns.form,
        context=ns.context,
        glossary=glossary,
        history_chars=ns.history_chars,
        dry_run=ns.dry_run,
        no_cache=ns.no_cache,
        report=ns.report,
    )


def _parse_html(path: Path) -> lxml.html.HtmlElement:
    try:
        data = path.read_bytes()
    except OSError as e:
        raise InputError(f"cannot read {path}: {e}") from e
    try:
        return lxml.html.document_fromstring(data)
    except (etree.ParserError, etree.XMLSyntaxError) as e:
        raise InputError(f"cannot parse {path} as HTML: {e}") from e


def _serialize(root: lxml.html.HtmlElement) -> bytes:
    tree = root.getroottree()
    return lxml.html.tostring(tree, encoding="utf-8", doctype=tree.docinfo.doctype)


def _progress(done: int, total: int) -> None:
    print(f"{done}/{total}", file=sys.stderr, flush=True)


def _run(opts: Options, client: TranslationClient, cache: TranslationCache) -> int:
    root = _parse_html(opts.input)
    units = extract_units(root)
    if opts.dry_run:
        print(dry_run_text(units))
        return EXIT_OK
    settings = Settings(opts.context, opts.form, opts.glossary, opts.history_chars)
    try:
        result = run_pipeline(units, client, cache, settings, _progress)
    except ServerUnreachable as e:
        print(
            f"error: {e}\nstart the server with: systemctl --user start plamo-llama-server",
            file=sys.stderr,
        )
        return EXIT_UNREACHABLE
    apply_translations(units, result.restored)
    root.set("lang", "ja")
    opts.output.write_bytes(_serialize(root))
    if opts.report is not None:
        opts.report.write_text(failures_json(result.failures), encoding="utf-8")
    print(summary_text(result.stats), file=sys.stderr)
    if result.stats.failed:
        print(f"warning: {result.stats.failed} block(s) left untranslated", file=sys.stderr)
    print(opts.output)
    return EXIT_OK


def main(
    argv: Sequence[str] | None = None,
    *,
    client: TranslationClient | None = None,
    cache: TranslationCache | None = None,
) -> int:
    try:
        opts = parse_options(argv)
        chosen_cache = cache or (NullCache() if opts.no_cache else FileCache(default_cache_path()))
        return _run(opts, client or HttpClient(opts.url), chosen_cache)
    except InputError as e:
        print(f"error: {e}", file=sys.stderr)
        return EXIT_INPUT_ERROR
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return EXIT_INPUT_ERROR
