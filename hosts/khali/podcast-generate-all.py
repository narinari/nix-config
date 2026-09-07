#!/usr/bin/env python3
"""hermes cron --no-agent runner: generate_all_today_episodes を直接呼ぶ。

hermes-daily-podcast-seed.service が ~/.hermes/scripts/ にインストールし、
`hermes cron create --no-agent --script` で毎晩実行される。

以前はエージェント会話 (27B が全ツール定義込み ~27k tokens を読んで推論)
経由でツールを 1 回呼んでいたが、プロンプトも呼ぶツールも固定の決定的な
ジョブなので LLM の関与は純粋な無駄だった。このスクリプトはプラグインの
handler を直接呼び、stdout を整形サマリとしてそのまま配信させる
(--no-agent は stdout をそのまま deliver する。空 stdout = silent なので
必ず 1 行以上出力する)。

エピソード内部の LLM 呼び出し (採点・要約) はプラグイン側で従来どおり
実行される — 削るのはエージェントループのオーバーヘッドだけ。
"""

from __future__ import annotations

import importlib
import importlib.util
import logging
import sys
from pathlib import Path

PLUGIN_DIR = (
    Path.home() / ".hermes" / "plugins" / "nix-managed-hermes-daily-podcast-plugin"
)
PKG = "daily_podcast_noagent"

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
        result = handlers.generate_all_today_episodes()
    except Exception as exc:  # noqa: BLE001 - 配信サマリに載せて必ず可視化する
        logging.getLogger(__name__).exception("generate_all_today_episodes crashed")
        print(f"🎧 daily-podcast: クラッシュ — {type(exc).__name__}: {exc}")
        return 1

    headline = (
        result.get("summary")
        or result.get("warning")
        or result.get("error")
        or "結果不明"
    )
    lines = [f"🎧 daily-podcast: {headline}"]
    for entry in result.get("results", []):
        slug = entry.get("topic_slug", "?")
        res = entry.get("result") or {}
        if "error" in res:
            lines.append(f"❌ {slug}: {res['error']}")
        else:
            lines.append(f"✅ {slug}: {res.get('title', '(no title)')}")
            if res.get("audio_url"):
                lines.append(f"   {res['audio_url']}")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
