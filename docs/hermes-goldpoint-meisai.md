# Hermes Agent — goldpoint-meisai (GOLD POINT CARD+ 明細自動取得)

khali の Hermes Agent に、GOLD POINT CARD+ (ヨドバシカメラのクレジットカード) の
利用明細CSVを毎月自動取得し Google Drive にアップロードさせる構成。
自作 plugin `pkgs/hermes-goldpoint-plugin/` (toolset: `goldpoint-meisai`) を使う。

## 構成概要

1. **認証情報取得**: plugin の `bw.py` が Bitwarden Password Manager の CLI `bw` で
   エージェント専用アカウントの vault を解錠し (`bw unlock --passwordfile $HERMES_BW_PASSWORD_FILE`)、
   `bw get item $GOLDPOINT_BW_ITEM_ID` でログイン ID / パスワードを取得する。
   アイテムの正本は narinari の vault (Families org の collection `hermes-agent`) で、
   複製はしない。基盤は `hosts/khali/hermes-bitwarden.nix` と
   [hermes-credential-vault.md](hermes-credential-vault.md) を参照。
2. **ログイン**: headless Chromium (退避用に Xvfb 上の headed も可) を起動し、CDP (Chrome DevTools Protocol) 経由で
   GOLD POINT CARD+ のログインフォームを自動入力・送信する
   (bot 対策の hidden→text 切り替えを poll、ページ内 JS 実行のみで完結)。
3. **CSV取得**: ログイン後、明細ページを開いてから同一セッションの `fetch()` で
   CSV API を叩き、Shift_JIS のバイト列をそのまま `$GOLDPOINT_STATE_DIR/csv/YYYY-MM.csv`
   に保存する (文字コード変換はしない)。
4. **Google Drive アップロード**: `googleapiclient` (drive v3、スコープ `drive.file` のみ)
   で `$GOLDPOINT_DRIVE_FOLDER` (既定 `家計/goldpoint`) 配下に
   `YYYY-MM.csv` として作成/上書きする。

tool: `goldpoint_fetch_statement(seikyuym?)` — `seikyuym` (YYYYMM) 省略時は
Asia/Tokyo の当月 (明細は毎月10日に確定する運用前提)。
定期実行は Hermes 内蔵 cron の `--no-agent` ジョブ `hermes-goldpoint-meisai-noagent`
(毎月11日 09:00 JST) で `hosts/khali/goldpoint-fetch-statement.py` を直接呼ぶ
(daily-podcast と同じ方針、詳細は `hosts/khali/goldpoint-timer.nix`)。

runner は `goldpoint_fetch_missing_statements` 相当を呼び、サイトの請求月セレクタに
ある月のうち `csv/` に無い月を全て取得する (取りこぼしの追いつき)。未確定の月
(CSV API が空ボディ) は保存せずスキップして次回に回す。Drive には `uploaded.txt`
に載っていない CSV だけをアップロードする。新規が無ければ
`新しい明細はありません` を出力する。Drive 失敗時は ⚠️ を出して exit 1、
次回の実行で未アップロード分を再送する。

- 特定月を再取得したい: `$GOLDPOINT_STATE_DIR/csv/YYYY-MM.csv` を削除する
  (次回実行で再取得。Drive へも再アップロードしたいなら `uploaded.txt` の該当行も削除)。
- Drive へ再アップロードしたい: `$GOLDPOINT_STATE_DIR/uploaded.txt` から該当ファイル名の行を削除する。

## 1. Bitwarden 側の準備

エージェントアカウント・collection・agenix secret の共通セットアップは
[hermes-credential-vault.md](hermes-credential-vault.md) の手順を先に済ませる。
goldpoint 固有の作業は次のとおり:

1. GOLD POINT CARD+ のログインアイテム (ユーザー名 = 会員番号、URI =
   `https://secure.goldpoint.co.jp`) を collection `hermes-agent` に移動する。
2. khali でアイテム ID を確認する:

   ```bash
   sudo -u hermes env HOME=/var/lib/hermes sh -c \
     'BW_SESSION=$(bw unlock --raw --passwordfile /run/agenix/hermes-bw-password) \
      && bw sync >/dev/null && bw list items --search goldpoint | jq -r ".[] | .id + \"  \" + .name"'
   ```

## 2. アイテム ID の設定

`hosts/khali/hermes-agent.nix` の `services.hermes-agent.environment` にある
`GOLDPOINT_BW_ITEM_ID` を手順 1 の ID に書き換えて rebuild する
(ID は秘密情報ではないので agenix には入れない)。

## 3. Google Drive 初回認可

goldpoint-meisai plugin は Gmail/Calendar 用の既存 token
(`/var/lib/hermes/.hermes/google_token.json`) とは **別ファイル**
(`$GOLDPOINT_STATE_DIR/gdrive_token.json`) を使う。スコープは `drive.file` のみ
(plugin がアップロードしたファイルにのみアクセス)。

1. GCP コンソールで **Google Drive API** を有効化する
   (`docs/hermes-google-workspace.md` の時点では Gmail API / Google Calendar API のみ
   有効化されているため、追加で有効化が必要)。
2. khali 上で `hermes` グループのユーザーとして認可 URL を発行する:

   ```bash
   sudo -u hermes env \
     HERMES_HOME=/var/lib/hermes/.hermes \
     GOLDPOINT_STATE_DIR=/var/lib/hermes-goldpoint \
     python3 /var/lib/hermes/.hermes/plugins/nix-managed-hermes-goldpoint-plugin/gdrive_setup.py --auth-url
   ```

3. 出力された URL をブラウザで開いて承認する。
4. リダイレクト先の URL (ブラウザのアドレスバーに表示される、そのまま丸ごと) を使って
   認可コードを渡す:

   ```bash
   sudo -u hermes env \
     HERMES_HOME=/var/lib/hermes/.hermes \
     GOLDPOINT_STATE_DIR=/var/lib/hermes-goldpoint \
     python3 /var/lib/hermes/.hermes/plugins/nix-managed-hermes-goldpoint-plugin/gdrive_setup.py \
       --auth-code '<リダイレクト先 URL をまるごと>'
   ```

5. `$GOLDPOINT_STATE_DIR/gdrive_token.json` が作成されれば完了
   (`--check` があれば状態確認に使う)。

この token は agenix でスナップショットしていない (状態ディレクトリの通常ファイルとして
永続化されるため、khali のディスクが失われない限り再認可は不要)。

## 4. 動作確認

1. `sudo nixos-rebuild switch` を khali で実行し、`hermes-goldpoint-seed.service` が
   一度走ることを確認する:

   ```bash
   systemctl status hermes-goldpoint-seed.service
   journalctl -u hermes-goldpoint-seed.service -n 50
   ```

2. cron job が登録されたか確認:

   ```bash
   sudo -u hermes hermes cron list | grep goldpoint
   # hermes-goldpoint-meisai-noagent が '0 9 11 * *' で表示されればOK
   ```

3. Discord または CLI から Hermes に「goldpoint_fetch_statement を呼んで」と依頼し、
   手動で1回動かしてみる (`seikyuym` を明示指定すれば過去月も取得可能、例:
   「goldpoint_fetch_statement を seikyuym=202608 で呼んで」)。

4. 実行ログの確認:

   ```bash
   journalctl -u hermes-agent -f | grep -i goldpoint
   ```

   成功時は `💳 goldpoint: <YYYYMM> 明細 <N>行 を Drive 家計/goldpoint/<YYYY-MM>.csv
   にアップロードしました` のようなサマリが返る。CSV の中身や認証情報はログ・戻り値
   どちらにも出力されない。

## 制限事項 / トラブルシュート

- **headless と headed**: 既定は headless で、UA は通常 Chrome 相当に差し替える
  (既定の HeadlessChrome UA だとページ取得自体が保留される)。下記の痕跡対策なしでは
  headless も headed もログイン POST が `Access Denied` だった (2026-11-10)。
  headless で弾かれる場合は `GOLDPOINT_HEADED=1` で Xvfb 上の headed に切り替えられる
  (`pkgs.xvfb` は extraPackages に入っている)。
- **自動操作の痕跡対策 (2026-11-10)**: JS で値を代入する送信は `Access Denied` になる。
  そのため次の対策を入れている。いずれもサイト側の検出更新で再び壊れうる。
  - CDP Input ドメインの実イベントによるクリック・タイプ (`human_input.py`、ランダム間隔)
  - `--disable-blink-features=AutomationControlled`
  - 入力前に 4〜7 秒滞在する
  - プロファイル `$GOLDPOINT_STATE_DIR/chromium-profile` (0700) を使い回し、Akamai cookie を引き継ぐ
- **ログイン失敗の切り分け**: エラー末尾の `[<パス> title=<タイトル> errors=<エラー表示>]` を見る。
  `title=Access Denied` ならボット判定、ログインページのままでエラー表示があれば入力値の問題。
- **Drive token 未認可エラー**: `goldpoint_fetch_statement` が
  `{"error": "...", "hint": "gdrive_setup.py を実行してください"}` のような戻り値を
  返した場合は、本ドキュメントの「3. Google Drive 初回認可」を再実行する。
- **Bitwarden 関連エラー** (`failed to load credentials`):
  - `bw is not logged in` → `systemctl status hermes-bw-login` を確認し、
    `sudo systemctl restart hermes-bw-login` で再ログイン。
  - `bw unlock failed` → `hermes-bw-password.age` の内容 (末尾改行なし) とエージェントアカウントのパスワード変更有無。
  - `bw get item failed` → `GOLDPOINT_BW_ITEM_ID` の誤り、またはアイテムが collection `hermes-agent` から外れている。
  - 切り分けは「1. Bitwarden 側の準備」の `bw list items` コマンドで行う (出力に値は含まれない)。
- **明細確定タイミング**: サイト側の運用に合わせ毎月10日確定 → 11日 09:00 JST に
  cron 実行としている。稀に確定が遅れる月がある場合は手動再実行 (上記「動作確認」の
  3番目) で対応する。
