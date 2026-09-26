# Hermes Agent — Google Workspace (Gmail / Calendar) 連携

khali の Hermes Agent に Google Calendar / Gmail アクセスを与える構成。
Hermes 同梱の bundled skill `productivity/google-workspace` を使う (MCP や自作 plugin は不使用)。

## 構成概要

- **skill**: `/var/lib/hermes/.hermes/skills/productivity/google-workspace/` (Hermes 0.21.0 に標準 seed)
- **実行系**: skill の `scripts/google_api.py` を Hermes の terminal ツールが実行する。
  Python 依存 (google-api-python-client / google-auth-oauthlib) は hermes-agent-env に同梱済みで追加パッケージ不要
- **認証**: GCP OAuth 2.0 Desktop クライアント + PKCE。token は自動 refresh
- **credential 配置** (いずれも `hermes` group が read/write できること):

| ファイル | 内容 | 由来 |
|---|---|---|
| `/var/lib/hermes/.hermes/google_client_secret.json` | OAuth クライアント (client_id/secret) | agenix seed または setup.py `--client-secret` |
| `/var/lib/hermes/.hermes/google_token.json` | access/refresh token。refresh で随時書き換わる | agenix seed (初回のみ) または認可フロー |

- **agenix**: `my-secrets/private/hermes-google-client-secret.json.age` / `hermes-google-token.json.age`。
  `hosts/khali/hermes-agent.nix` の `hermes-agent-credentials` oneshot が **ファイルが無い場合のみ** seed する
  (token は refresh で書き換わるため上書きしない — hermes-claude-credentials と同じ方針)

## 認可スコープ

この Hermes 版の `setup.py` はスコープ固定 (SKILL.md 記載の `--services` 絞り込みは未実装):
gmail.readonly / gmail.send / gmail.modify / calendar / drive.readonly / contacts.readonly / spreadsheets / documents.readonly

実際に使える範囲は **GCP 側で有効化した API で制限**している (Gmail API + Google Calendar API のみ有効。
Drive/Sheets/Docs/People は API 未有効化のため呼んでも 403)。

## GCP 側の設定 (narinari.t@gmail.com)

- プロジェクトの OAuth クライアント: Desktop app `222788196379-hv2ked55kvekjvi6cufcj6u443rt9gtv`
- 有効 API: Gmail API, Google Calendar API
- **注意**: OAuth consent screen が「テスト中 (Testing)」のままだと refresh token が **7 日で失効**する。
  長期運用するには Audience を「本番環境 (In production)」に publish しておくこと (未検証アプリ警告は個人利用なら許容)

## 再認可の手順 (token 失効時: `REFRESH_FAILED` / `invalid_grant`)

hermes group に属するユーザーで khali 上で実行:

```bash
PY=$(ls -d /nix/store/*hermes-agent-env*/bin/python3 | head -1)   # または hermes サービスと同じ env
export HERMES_HOME=/var/lib/hermes/.hermes
S=$HERMES_HOME/skills/productivity/google-workspace/scripts/setup.py
umask 007

$PY $S --check                 # 状態確認
$PY $S --auth-url              # → 出力 URL をブラウザで開いて承認
$PY $S --auth-code '<リダイレクト先 URL をまるごと>'
$PY $S --check                 # AUTHENTICATED になれば完了
```

その後、新しい token を my-secrets に反映:

```bash
cd ~/nix-secrets
rage -r "$(awk '{print $1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub) root@khali" \
     -r "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICedOiRH96VIeFYIzMGPPCG2MLYhZkolBbl4wwtY8/A8 narinari.t@gmail.com" \
     -o private/hermes-google-token.json.age /var/lib/hermes/.hermes/google_token.json
git commit -am 'chore: refresh hermes google token' && git push
# nix-config 側: cd ~/nix-config/infra && nix flake update my-secrets
```

## アクセスの取り消し

```bash
$PY $S --revoke   # Google 側の token 失効 + ローカル token 削除
```

または https://myaccount.google.com/permissions からアプリのアクセス権を削除。

## 使い方 (Hermes 側)

Hermes は依頼に応じて skill を自動ロードする。skill 側ルールで「メール送信・イベント作成/削除は
実行前にユーザー確認必須」となっている。Gmail 検索構文は skill の
`references/gmail-search-syntax.md` を参照。

## セキュリティ上の注意

- gmail.modify スコープはメールの既読化・アーカイブ・ラベル操作まで可能 (完全削除は不可)
- メール本文はプロンプトインジェクションの入口になり得る。Hermes に「メールを読んで◯◯して」と
  依頼する際、本文中の指示に従わせない前提 (skill ルールの送信前確認) が防波堤になっている
- 将来スコープを絞りたい場合は upstream の `--services` 対応版への更新を検討
  (SKILL.md には記載済みなので、hermes-agent input の更新で入る可能性が高い)
