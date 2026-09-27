# hermes-goldpoint-plugin

Hermes Agent プラグイン。GOLD POINT CARD+ (ヨドバシ) の利用明細 CSV を
毎月自動取得し、Google Drive の `家計/goldpoint/YYYY-MM.csv` にアップロード
する。ログインフォームは JS による bot 対策 (hidden→text 書き換え、乱数
トークン埋め込み) があり HTTP 直叩きでは再現できないため、headless Chromium
+ CDP (`websockets`) で実ブラウザ相当のフォーム入力を行う。

## 設計方針

- **認証情報はモデルに渡さない**: パスワード・ID は Bitwarden Secrets
  Manager (`bws` CLI) から実行時に取得する。tool の呼び出しパラメータには
  含まれない。
- **CSV 内容 / パスワード / BWS トークンはログにも戻り値にも出さない**。
  ログイン失敗時の CDP 例外メッセージは入力値混入のリスクがあるため、
  自前の汎用メッセージに変換して伝播する (詳細: `goldpoint.py` docstring)。
- **サイト仕様は貴重なリバースエンジニアリング成果物**: セレクタ・URL・
  bot 対策の回避手順は `src/goldpoint.py` の docstring に要約してある。
  実装を変更する際もこの制約は変えないこと。

## 公開する Hermes tool

| name | 役割 | 破壊性 |
| --- | --- | --- |
| `goldpoint_fetch_statement(seikyuym?)` | 指定請求月の明細 CSV を取得し保存 + Drive アップロード | CSV ファイル・Drive 上のファイルを上書き |

`seikyuym` (YYYYMM, 6桁数字) を省略すると Asia/Tokyo の当月分になる
(毎月10日に当月分が確定する運用前提)。

## 必要な環境変数

| 変数 | 必須 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `GOLDPOINT_STATE_DIR` | no | `/var/lib/hermes-goldpoint` | CSV (`csv/YYYY-MM.csv`) と `gdrive_token.json` を置くルート |
| `GOLDPOINT_DRIVE_FOLDER` | no | `家計/goldpoint` | アップロード先の Drive フォルダパス (`/` 区切り、マイドライブ直下から) |
| `GOLDPOINT_BWS_SECRET_ID` | yes | — | ログイン ID (authKey) を保持する Bitwarden Secrets Manager の secret UUID |
| `GOLDPOINT_BWS_SECRET_PASSWORD` | yes | — | ログインパスワードを保持する secret UUID |
| `BWS_ACCESS_TOKEN` | yes | — | `bws` CLI の認証トークン (agenix 経由で供給) |
| `GOLDPOINT_CHROMIUM` | no | `AGENT_BROWSER_EXECUTABLE_PATH` → `chromium` | headless Chromium バイナリの明示指定 |
| `HERMES_HOME` | no | `~/.hermes` | `google_client_secret.json` の置き場所 (google-workspace skill と共用) |

## セットアップ手順

### 1. Bitwarden Secrets Manager に ID / パスワードを登録

Bitwarden Secrets Manager の Web UI (または `bws` CLI) で、GOLD POINT
CARD+ のログイン ID と パスワードをそれぞれ別の secret として作成し、
発行された UUID を控える。

```bash
# 例 (bws CLI がローカルにあれば)
bws secret create <project-id> goldpoint-auth-key '<ログインID>'
bws secret create <project-id> goldpoint-password '<パスワード>'
```

得られた 2 つの secret UUID を `GOLDPOINT_BWS_SECRET_ID` /
`GOLDPOINT_BWS_SECRET_PASSWORD` として Nix 側 (agenix env) に設定する。
`BWS_ACCESS_TOKEN` は既存の `bws` CLI 認証セットアップに従う。

### 2. Google Drive の認可 (初回のみ)

`google-workspace` bundled skill と同じ `$HERMES_HOME/google_client_secret.json`
(GCP OAuth Desktop クライアント) を使い回す。まだ無ければ google-workspace
skill のセットアップ手順に従って用意する。

khali (ヘッドレスサーバ) 上で実行する想定のため、ローカルサーバを起動して
リダイレクトを自動受信する `InstalledAppFlow` は使わず、URL を手動でコピペ
する方式にしてある。

```bash
# khali 上での実運用コマンドは docs/hermes-goldpoint-meisai.md を参照
# (sudo -u hermes env HERMES_HOME=... GOLDPOINT_STATE_DIR=... python3 <設置先>/gdrive_setup.py ...)
GDS=/var/lib/hermes/.hermes/plugins/nix-managed-hermes-goldpoint-plugin/gdrive_setup.py

# 1. 認可 URL を表示
python3 $GDS --auth-url

# 2. 表示された URL をブラウザで開いて認可

# 3. 認可後にブラウザが遷移する (到達エラーになる) http://localhost:1/... の
#    URL 全体をコピーして渡す
python3 $GDS --auth-code 'http://localhost:1/?state=...&code=...'

# 4. token が保存されたか確認
python3 $GDS --check
```

token は `$GOLDPOINT_STATE_DIR/gdrive_token.json` に保存され、以後は
refresh token で自動更新される (更新時に同ファイルへ書き戻す)。

### 3. khali host への統合

`hosts/khali/hermes-agent.nix` 側で以下を行う (家族向け plugin と同じパターン):

- `pkgs.callPackage ../../pkgs/hermes-goldpoint-plugin { }` を
  `extraPlugins` に追加
- `toolsets` / `plugins.enabled` に `"goldpoint-meisai"` を追加
- 非機密 env (`GOLDPOINT_STATE_DIR` 等) は `environment` に、
  secret env (`GOLDPOINT_BWS_SECRET_ID` / `GOLDPOINT_BWS_SECRET_PASSWORD` /
  `BWS_ACCESS_TOKEN`) は agenix 経由の `environmentFiles` に追加する
- `extraPackages` に `bws` CLI と `chromium` (未追加であれば) を追加
- Python 依存 (`websockets` / `google-api-python-client` / `google-auth-oauthlib`)
  は hermes-agent-env に同梱済みのため追加不要 (plugin handler は Hermes
  プロセス内で import する)

```bash
cd /home/narinari/nix-config
nix build --no-link --print-out-paths .#packages.x86_64-linux.hermes-goldpoint-plugin
sudo nixos-rebuild build --flake .#khali   # ドライラン
sudo nixos-rebuild switch --flake .#khali
journalctl -u hermes-agent -f | grep -i goldpoint
```

## トラブルシューティング

| 症状 | 原因の見当 |
| --- | --- |
| `failed to load credentials` | `GOLDPOINT_BWS_SECRET_ID` / `GOLDPOINT_BWS_SECRET_PASSWORD` / `BWS_ACCESS_TOKEN` の未設定、または `bws` バイナリが PATH に無い |
| `login failed: did not reach membertop.html` | ログイン ID/パスワードの誤り、またはサイト側フォーム仕様の変更。パスワード自体はエラーメッセージに含まれない |
| `failed to fill login form` | サイトの bot 対策 JS (`authenticateDO.authKey` の type 書き換え) がタイムアウト内に完了しなかった、またはページ構造が変わった |
| `chromium binary not found` | `GOLDPOINT_CHROMIUM` / `AGENT_BROWSER_EXECUTABLE_PATH` が指す実行ファイルが存在しない |
| `CSV API request failed (status=...)` | セッション切れ、または請求月 (`seikyuym`) がまだ確定していない (毎月10日頃まで前月分しか無いことがある) |
| `gdrive token not found` / `Drive upload failed` | `gdrive_setup.py --auth-url` / `--auth-code` を実行して初回認可を完了させる |

## ファイルレイアウト

```
hermes-goldpoint-plugin/
├── default.nix          # Nix derivation (runCommand で src/ を $out/ にコピー)
├── README.md            # 本ファイル
└── src/
    ├── plugin.yaml       # Hermes plugin manifest
    ├── __init__.py       # register(ctx) + _safe_handler + tool schema
    ├── config.py         # env 読み (GOLDPOINT_STATE_DIR 等)
    ├── bws.py            # bws secret get ラッパー
    ├── cdp.py            # headless Chromium 起動 + CDP (websockets) クライアント
    ├── goldpoint.py      # ログイン → CSV fetch → ログアウト (サイト仕様の要約はここ)
    ├── gdrive.py         # Drive token 管理 + フォルダ確保 + アップロード
    ├── gdrive_setup.py   # 初回 Drive 認可 CLI (--check / --auth-url / --auth-code)
    └── handlers.py       # goldpoint_fetch_statement ハンドラ
```
