#!/usr/bin/env python3
"""hermes cron --no-agent runner: handlers.fetch_missing_statements() を直接呼ぶ。

hermes-goldpoint-seed.service が ~/.hermes/scripts/ にインストールし、
`hermes cron create --no-agent --script` で毎月11日 09:00 JST に実行される
(明細は毎月10日に確定する運用のため)。
サイトに表示される請求月のうちローカル未保存の月を全て取得 (取りこぼしの追いつき) し、
未確定の月 (CSV が空) はスキップして次回に回す。Drive 未アップロードの CSV
(uploaded.txt に未記載) もまとめてアップロードする。

daily-podcast-generate-all.py と同じ方針: プロンプトも呼ぶツールも固定の
決定的なジョブなので、エージェント LLM の関与は無駄。このスクリプトは
プラグインの handler を直接呼び、stdout を整形サマリとしてそのまま配信させる
(--no-agent は stdout をそのまま deliver する。空 stdout = silent なので
必ず 1 行以上出力する)。

CSV の中身・認証情報 (bw session key / マスターパスワード、ログインパスワード等) は絶対に stdout /
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
        result = handlers.fetch_missing_statements()
    except Exception as exc:  # noqa: BLE001 - 配信サマリに載せて必ず可視化する
        logging.getLogger(__name__).exception("fetch_missing_statements crashed")
        print(f"💳 goldpoint: クラッシュ — {type(exc).__name__}: {exc}")
        return 1

    if "error" in result:
        lines = [f"❌ goldpoint: {result['error']}"]
        hint = result.get("hint")
        if hint:
            lines.append(f"   hint: {hint}")
        print("\n".join(lines))
        return 1

    lines = _summary_lines(result)
    upload_error = result.get("upload_error")
    if upload_error:
        lines.append(f"⚠️ goldpoint: {upload_error}")
        hint = result.get("hint")
        if hint:
            lines.append(f"   hint: {hint}")
    print("\n".join(lines))
    return 1 if upload_error else 0


def _summary_lines(result: dict) -> list[str]:
    fetched = result.get("fetched", [])
    skipped = result.get("skipped_not_ready", [])
    uploaded = result.get("uploaded", [])
    pending = result.get("pending_upload", [])
    if not (fetched or uploaded or pending):
        return ["💳 goldpoint: 新しい明細はありません"]
    folder = result.get("drive_folder", "?")
    lines = ["💳 goldpoint: 明細を更新しました"]
    if fetched:
        lines.append(f"   取得: {', '.join(fetched)}")
    if skipped:
        lines.append(f"   未確定のためスキップ: {', '.join(skipped)}")
    if uploaded:
        lines.append(f"   Drive {folder} にアップロード: {', '.join(uploaded)}")
    if pending:
        lines.append(f"   未アップロード: {', '.join(pending)}")
    return lines


if __name__ == "__main__":
    sys.exit(main())
