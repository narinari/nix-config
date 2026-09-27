# Hermes Agent — goldpoint-meisai (GOLD POINT CARD+ 明細自動取得)

khali の Hermes Agent に、GOLD POINT CARD+ (ヨドバシカメラのクレジットカード) の
利用明細CSVを毎月自動取得し Google Drive にアップロードさせる構成。
自作 plugin `pkgs/hermes-goldpoint-plugin/` (toolset: `goldpoint-meisai`) を使う。

## 構成概要

1. **認証情報取得**: plugin の `bws.py` が `bws secret get <secret-id> --output json`
   を subprocess で呼び、Bitwarden Secrets Manager からログイン ID / パスワードを取得する
   (`BWS_ACCESS_TOKEN` で bws CLI 自体を認証)。
2. **ログイン**: headless Chromium を起動し、CDP (Chrome DevTools Protocol) 経由で
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

## 1. Bitwarden Secrets Manager 側の準備

1. https://bitwarden.com でアカウント/組織を作成 (個人利用なら Free プランで可)。
2. 組織の **Secrets Manager** を有効化する。
3. プロジェクトを作成する (例: `goldpoint`)。
4. シークレットを2つ登録する:
   - `goldpoint-id` — GOLD POINT CARD+ のログイン ID (会員番号)
   - `goldpoint-password` — ログインパスワード
5. **マシンアカウント** を作成し、上記プロジェクトへの **read** 権限を付与する。
6. マシンアカウントの **アクセストークン** を発行する (`BWS_ACCESS_TOKEN` として使う)。
7. `goldpoint-id` / `goldpoint-password` それぞれの **シークレット ID (UUID)** を控える
   (`GOLDPOINT_BWS_SECRET_ID` / `GOLDPOINT_BWS_SECRET_PASSWORD` として使う)。

## 2. `goldpoint-env.age` の作成

他の env 系 secret (`family-inventory-agent-env.age` 等) と同じく、
my-secrets リポジトリ (`~/nix-secrets` 想定) に agenix で暗号化して置く。

```bash
cd ~/nix-secrets
agenix -e private/goldpoint-env.age
# エディタが開いたら以下の形式で保存 (それぞれ手順1で控えた値に置き換える):
# BWS_ACCESS_TOKEN=<マシンアカウントのアクセストークン>
# GOLDPOINT_BWS_SECRET_ID=<goldpoint-id シークレットの UUID>
# GOLDPOINT_BWS_SECRET_PASSWORD=<goldpoint-password シークレットの UUID>

git add private/goldpoint-env.age
git commit -m "feat: add goldpoint-meisai bws credentials"
git push
```

nix-config 側で lock を更新して取り込む。khali は workstations flake 定義のため
2 段階の relock が必要 (トップ flake.lock には my-secrets ノードが複製されるため、
workstations 側だけでは反映されない — 過去の対応は e4fba6b / c06fc71 を参照):

```bash
cd ~/nix-config/workstations && nix flake update my-secrets
cd ~/nix-config && nix flake update my-secrets
```

`hosts/khali/hermes-agent.nix` 側は既に以下を参照する設定済み:

- `age.secrets."goldpoint-env" = { file = "${inputs.my-secrets}/private/goldpoint-env.age"; };`
- `services.hermes-agent.environmentFiles` 内の
  `config.age.secrets."goldpoint-env".path`

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

- **headless=new でのログイン失敗**: サイトの bot 対策 (ID欄が type=hidden → text へ
  JS で切り替わる) は headed CDP (画面ありの Chromium) では突破できているが、
  `--headless=new` では未検証/失敗する可能性が残る。ログイン失敗
  (`membertop.html` へ遷移しなかった) が続く場合は、`GOLDPOINT_CHROMIUM` env を
  Xvfb 等でラップした headed 起動用スクリプトに差し替えることを検討する
  (`AGENT_BROWSER_EXECUTABLE_PATH` と同じ仕組みで上書き可能)。
- **Drive token 未認可エラー**: `goldpoint_fetch_statement` が
  `{"error": "...", "hint": "gdrive_setup.py を実行してください"}` のような戻り値を
  返した場合は、本ドキュメントの「3. Google Drive 初回認可」を再実行する。
- **BWS 関連エラー**: `bws secret get` が失敗する場合、`BWS_ACCESS_TOKEN` の失効/
  シークレット ID の誤り/マシンアカウントの権限不足を疑う。
  `sudo -u hermes env BWS_ACCESS_TOKEN=... bws secret get <id>` で直接切り分け可能
  (出力に値が含まれるため、ターミナル履歴の扱いに注意)。
- **明細確定タイミング**: サイト側の運用に合わせ毎月10日確定 → 11日 09:00 JST に
  cron 実行としている。稀に確定が遅れる月がある場合は手動再実行 (上記「動作確認」の
  3番目) で対応する。
