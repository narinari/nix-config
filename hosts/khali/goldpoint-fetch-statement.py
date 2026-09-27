#!/usr/bin/env python3
"""hermes cron --no-agent runner: handlers.fetch_statement() を直接呼ぶ。

hermes-goldpoint-seed.service が ~/.hermes/scripts/ にインストールし、
`hermes cron create --no-agent --script` で毎月11日 09:00 JST に実行される
(明細は毎月10日に確定する運用のため)。

daily-podcast-generate-all.py と同じ方針: プロンプトも呼ぶツールも固定の
決定的なジョブなので、エージェント LLM の関与は無駄。このスクリプトは
プラグインの handler を直接呼び、stdout を整形サマリとしてそのまま配信させる
(--no-agent は stdout をそのまま deliver する。空 stdout = silent なので
必ず 1 行以上出力する)。

CSV の中身・認証情報 (BWS トークン、ログインパスワード等) は絶対に stdout /
ログに出力しない。ログイン失敗等の例外メッセージも handlers 側で
サニタイズ済みの前提で、そのまま日本語サマリに載せる。
"""

from __future__ import annotations

import importlib
import importlib.util
import logging
import sys
from pathlib import Path

PLUGIN_DIR = Path.home() / ".hermes" / "plugins" / "nix-managed-hermes-goldpoint-plugin"
PKG = "goldpoint_meisai_noagent"

# プラグインのログは stderr へ (journal で追える)。stdout は配信内容専用。
logging.basicConfig(
    level=logging.INFO,
    stream=sys.stderr,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


def _load_handlers():
    spec = importlib.util.spec_from_file_location(
        PKG,
        PLUGIN_DIR / "__init__.py",
        submodule_search_locations=[str(PLUGIN_DIR)],
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"plugin not found at {PLUGIN_DIR}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[PKG] = module
    spec.loader.exec_module(module)
    return importlib.import_module(f"{PKG}.handlers")


def main() -> int:
    try:
        handlers = _load_handlers()
        result = handlers.fetch_statement()
    except Exception as exc:  # noqa: BLE001 - 配信サマリに載せて必ず可視化する
        logging.getLogger(__name__).exception("fetch_statement crashed")
        print(f"💳 goldpoint: クラッシュ — {type(exc).__name__}: {exc}")
        return 1

    if "error" in result:
        lines = [f"❌ goldpoint: {result['error']}"]
        hint = result.get("hint")
        if hint:
            lines.append(f"   hint: {hint}")
        print("\n".join(lines))
        return 1

    seikyuym = result.get("seikyuym", "?")
    rows = result.get("rows", "?")
    drive_folder = result.get("drive_folder", "?")
    drive_file = result.get("drive_file", "?")
    saved_path = result.get("saved_path")

    lines = [
        f"💳 goldpoint: {seikyuym} 明細 {rows}行 を Drive {drive_folder}/{drive_file} にアップロードしました"
    ]
    if saved_path:
        lines.append(f"   local: {saved_path}")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
