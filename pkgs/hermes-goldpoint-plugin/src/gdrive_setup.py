#!/usr/bin/env python3
"""初回 Google Drive 認可 CLI。

`InstalledAppFlow` (ローカルサーバを起動してリダイレクトを自動受信する方式)
ではなく `Flow` + `redirect_uri=http://localhost:1` を使い、認可後にブラウザ
が遷移する (到達不能な) リダイレクト URL を手動でコピペしてもらう方式にする。
ヘッドレスサーバ上 (khali) での認可を想定しているため。

実運用ではファイルを直接実行する (詳細: docs/hermes-goldpoint-meisai.md):

    sudo -u hermes env \\
      HERMES_HOME=/var/lib/hermes/.hermes \\
      GOLDPOINT_STATE_DIR=/var/lib/hermes-goldpoint \\
      python3 /var/lib/hermes/.hermes/plugins/nix-managed-hermes-goldpoint-plugin/gdrive_setup.py --auth-url

    sudo -u hermes env \\
      HERMES_HOME=/var/lib/hermes/.hermes \\
      GOLDPOINT_STATE_DIR=/var/lib/hermes-goldpoint \\
      python3 /var/lib/hermes/.hermes/plugins/nix-managed-hermes-goldpoint-plugin/gdrive_setup.py \\
        --auth-code '<リダイレクト先 URL をまるごと>'

    python3 .../nix-managed-hermes-goldpoint-plugin/gdrive_setup.py --check

設置先ディレクトリ名 (`nix-managed-hermes-goldpoint-plugin`) はハイフン入り
のため `python3 -m <pkg>.gdrive_setup` は使えない。本ファイルはこの直接実行
を第一級の使い方として扱うため、`__package__` が空の場合は自分のディレクト
リを importlib で package 登録してから絶対 import する (下記 bootstrap)。

依存 `google_auth_oauthlib` はモジュールトップで import すると、
ライブラリ未インストールの環境で py_compile が通らないため、
実際に使う関数内でのみ import する。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

if __package__ in (None, ""):
    # ファイル直接実行 (上記の運用手順) 用 bootstrap。設置先ディレクトリ名は
    # ハイフン入りで python module 名にできず `-m` 実行もできないため、
    # hosts/khali/goldpoint-fetch-statement.py `_load_handlers()` と同じ方式
    # で自分自身のディレクトリを package として登録してから import し直す。
    import importlib.util

    _pkg_dir = Path(__file__).resolve().parent
    _spec = importlib.util.spec_from_file_location(
        "goldpoint_meisai_plugin",
        _pkg_dir / "__init__.py",
        submodule_search_locations=[str(_pkg_dir)],
    )
    if _spec is None or _spec.loader is None:
        raise RuntimeError(f"failed to load plugin package from {_pkg_dir}")
    _module = importlib.util.module_from_spec(_spec)
    sys.modules["goldpoint_meisai_plugin"] = _module
    _spec.loader.exec_module(_module)

    from goldpoint_meisai_plugin import config as cfg
    from goldpoint_meisai_plugin.gdrive import DRIVE_FILE_SCOPE
else:
    from . import config as cfg
    from .gdrive import DRIVE_FILE_SCOPE

REDIRECT_URI = "http://localhost:1"
PENDING_FILENAME = "gdrive_auth_pending.json"


def _pending_path():
    # --auth-url で生成した PKCE code_verifier と state を --auth-code まで保持する。
    return cfg.state_dir() / PENDING_FILENAME


def _load_client_config() -> dict:
    path = cfg.google_client_secret_path()
    if not path.exists():
        raise SystemExit(f"client secret not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _build_flow(**kwargs: object) -> object:
    from google_auth_oauthlib.flow import Flow

    client_config = _load_client_config()
    return Flow.from_client_config(
        client_config, scopes=[DRIVE_FILE_SCOPE], redirect_uri=REDIRECT_URI, **kwargs
    )


def cmd_check() -> int:
    token_path = cfg.gdrive_token_path()
    if not token_path.exists():
        print(f"NOT AUTHORIZED: token not found at {token_path}")
        return 1
    print(f"token present: {token_path}")
    return 0


def cmd_auth_url() -> int:
    flow = _build_flow()
    auth_url, state = flow.authorization_url(access_type="offline", prompt="consent")
    pending = _pending_path()
    pending.parent.mkdir(parents=True, exist_ok=True)
    pending.touch(mode=0o600, exist_ok=True)
    pending.chmod(0o600)
    pending.write_text(
        json.dumps({"state": state, "code_verifier": flow.code_verifier}),
        encoding="utf-8",
    )
    print(auth_url)
    print(
        "\nブラウザで上記 URL を開いて認可し、リダイレクト先の URL "
        "(http://localhost:1/... で到達エラーになるページの URL) をコピーして"
        "\n  --auth-code '<そのURL>' で渡してください。"
    )
    return 0


def cmd_auth_code(redirect_response: str) -> int:
    pending = _pending_path()
    if not pending.exists():
        raise SystemExit("--auth-url を先に実行してください (PKCE 情報が見つかりません)")
    saved = json.loads(pending.read_text(encoding="utf-8"))
    # リダイレクト先は http://localhost:1 (到達しないループバック)。oauthlib は
    # http を拒否するため、このプロセス内に限って許可する。
    os.environ["OAUTHLIB_INSECURE_TRANSPORT"] = "1"
    flow = _build_flow(state=saved["state"], code_verifier=saved["code_verifier"])
    flow.fetch_token(authorization_response=redirect_response)
    pending.unlink(missing_ok=True)
    creds = flow.credentials
    token_path = cfg.gdrive_token_path()
    token_path.parent.mkdir(parents=True, exist_ok=True)
    token_path.touch(mode=0o600, exist_ok=True)
    token_path.chmod(0o600)  # refresh_token を含むため
    token_path.write_text(creds.to_json(), encoding="utf-8")
    print(f"authorized. token saved to {token_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--check", action="store_true", help="token の有無だけ確認する"
    )
    group.add_argument(
        "--auth-url", action="store_true", help="認可用 URL を表示する"
    )
    group.add_argument(
        "--auth-code",
        metavar="REDIRECT_URL",
        help="認可後にブラウザが遷移したリダイレクト URL を渡して token を保存する",
    )
    args = parser.parse_args(argv)

    if args.check:
        return cmd_check()
    if args.auth_url:
        return cmd_auth_url()
    return cmd_auth_code(args.auth_code)


if __name__ == "__main__":
    sys.exit(main())
