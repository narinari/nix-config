# Hermes Agent ⇄ Claude Code Bridge

khali ホストで動いている **Hermes Agent** (NousResearch / `services.hermes-agent`) から、複雑な設計・アーキテクチャ判断・大規模リファクタリング計画などの **重い推論タスク** を **Claude Code (Opus 4.7)** に委譲する仕組み。Hermes は対話・スケジューリング・tool 実行の土台 (qwen3.6 via Aperture) を担い、設計判断は外部 LLM サブエージェントに任せる。

関連ドキュメント:
- 計画ドキュメント: `~/.claude/plans/hermes-agent-claude-code-hermes-claude-c-misty-milner.md`
- Phase 3 SmolVM サンドボックス計画: [`hermes-agent-phase3-smolvm.md`](./hermes-agent-phase3-smolvm.md)

## アーキテクチャ

```
narinari (terminal)
    │
    ▼ hermes CLI (PATH=...claude-code...)
hermes-agent.service (systemd, qwen3.6 via Aperture)
    │
    │ tool: claude_code(task, working_directory, context_files, ...)
    ▼
hermes-claude-code-plugin (extraPlugins, directory plugin)
    │
    │ subprocess: claude --print --output-format stream-json --model claude-opus-4-7 ...
    ▼
claude (Claude Code CLI, hermes user, CLAUDE_CONFIG_DIR=/var/lib/hermes/.claude)
    │
    │ OAuth (Pro/Max sub) — credentials.json は agenix snapshot 由来
    ▼
Anthropic API
```

実装場所:
- Plugin source: [`pkgs/hermes-claude-code-plugin/`](../pkgs/hermes-claude-code-plugin/)
- NixOS service: [`hosts/khali/hermes-agent.nix`](../hosts/khali/hermes-agent.nix)
- 認証 secret: `inputs.my-secrets/private/hermes-claude-credentials.json.age` (別 flake)

## Tool 仕様 — `claude_code`

| パラメータ | 型 | 必須 | 既定 | 説明 |
|---|---|---|---|---|
| `task` | string | ✅ | — | 委譲タスク本文。背景・制約・期待アウトプット形式を含めること |
| `working_directory` | string |  | hermes の cwd | 実行ディレクトリ (絶対パス)。git worktree もここで切り替える |
| `context_files` | string[] |  | `[]` | 参考ファイルの絶対パス。task に "Context files" 節として追記され、Claude Code 側で Read される |
| `resume_session_id` | string |  | — | 前回の `session_id` を渡すと会話継続 (毎 resume で前回履歴ぶんのコストが累積するので必要時のみ) |
| `timeout_seconds` | integer |  | 900 | 実行壁時計タイムアウト。最大 1800。超過時は subprocess を kill して部分結果返却 |

戻り値 (JSON):

```json
{
  "result": "Markdown 形式の応答テキスト",
  "session_id": "uuid",
  "model": "claude-opus-4-7",
  "cost_usd": 0.1234,
  "exit_code": 0,
  "elapsed_ms": 38542,
  "stderr_tail": "(末尾 2KB)"
}
```

モデルは plugin 側で `claude-opus-4-7` 固定 (LLM が tool 引数で変更できない)。切り替えたいときは hermes-agent.nix の `environment.HERMES_CLAUDE_CODE_MODEL` を編集する。

### 許可/拒否ツール (Claude Code 側)

`tools.py` の `ALLOWED_TOOLS` / `DISALLOWED_TOOLS` 定数と、`/var/lib/hermes/.claude/settings.json` の両方で防衛する。前者は CLI フラグで強制、後者は claude が global 設定として読む。

許可 (allow):
- `Read(**)`, `Edit(**)`, `Write(**)`, `Glob`, `Grep`
- `Bash(git log:*)`, `Bash(git diff:*)`, `Bash(git status:*)`, `Bash(git show:*)`
- `Bash(rg:*)`, `Bash(fd:*)`, `WebFetch`

拒否 (deny):
- `Read(**/.env)`, `Read(**/.env.*)`, `Read(**/secrets/**)`
- `Bash(rm:*)`, `Bash(curl:*)`, `Bash(wget:*)`, `Bash(sudo:*)`, `Bash(systemctl:*)`, `Bash(nix-env:*)`
- `Bash(claude:*)` (再帰委譲の物理ブロック)

## セットアップ手順

### 1. Claude Code OAuth credentials を my-secrets に登録 (初回のみ)

narinari の Pro/Max sub で生成した credentials を agenix で暗号化する:

```bash
# narinari 側で fresh な credentials を取得 (必要に応じて)
claude logout && claude login

# my-secrets リポジトリで暗号化登録
cd <my-secrets repo>
agenix -e private/hermes-claude-credentials.json.age
# (エディタが開く) → /home/narinari/.claude/.credentials.json の中身を貼り付けて保存

git add private/hermes-claude-credentials.json.age
git commit -m "feat: add hermes claude code credentials"
git push
```

`secrets.nix` (or recipients を管理する任意のファイル) で、khali ホストの SSH host key (`/etc/ssh/ssh_host_ed25519_key.pub`) と narinari の personal SSH 公開鍵を recipients に含めること。`friday-hermes-env.age` と同じセットでよい。

### 2. nix-config 側で flake.lock 更新 + rebuild

```bash
cd /home/narinari/nix-config
nix flake update my-secrets

# build だけ先に試す (eval + agenix 復号は activation 時)
nix build --impure .#nixosConfigurations.khali.config.system.build.toplevel

# 適用
sudo nixos-rebuild switch --flake .#khali
```

### 3. credentials seed の確認

```bash
sudo systemctl status hermes-agent-credentials   # oneshot, success
sudo ls -la /var/lib/hermes/.claude/             # .credentials.json (0600 hermes:hermes)、settings.json
```

`hermes-agent-credentials.service` は `before = [ "hermes-agent.service" ]` で先行する oneshot。既存 `.credentials.json` があれば上書きしない (refresh 後の最新トークンを尊重)。`settings.json` (permissions) は毎回上書き — Nix が source of truth。

### 4. hermes user で claude が起動するか smoke test

```bash
sudo -u hermes -i bash -lc \
  'CLAUDE_CONFIG_DIR=/var/lib/hermes/.claude claude --print --output-format json -p "say hi in japanese"'
```

JSON が返り `not authenticated` / `401` が出ないこと、permission prompt で hang しないことを確認。

### 5. plugin 認識 + delegate E2E

```bash
sudo systemctl restart hermes-agent
journalctl -u hermes-agent -b | grep -E "plugin|claude-code"

# 対話で確認
hermes
> pkgs/obscura/default.nix の構造を claude_code に渡してレビューさせて
```

期待:
- `claude_code` tool が呼ばれる
- stream-json の text_delta が hermes 出力に段階的に流れる
- 結果に `session_id` / `cost_usd` が付与
- `journalctl -u hermes-agent` に `hermes.plugin.claude_code` ロガーから構造化ログ:
  ```
  claude_code call: parent_session=... task_id=... delegated_session=... model=claude-opus-4-7 cost_usd=0.1234 exit_code=0 elapsed_ms=38542 task=...
  ```

## 運用

### Credentials の更新フロー

token rotation 衝突や手動更新が必要になったとき:

```bash
# 1. narinari 側で再 login
claude logout && claude login

# 2. my-secrets の暗号化を更新
cd <my-secrets repo>
agenix -e private/hermes-claude-credentials.json.age   # 新しい中身を貼り付け
git commit -am "chore: refresh hermes claude code credentials" && git push

# 3. nix-config を更新
cd /home/narinari/nix-config
nix flake update my-secrets

# 4. hermes 側の working copy を消してから再 seed
sudo rm /var/lib/hermes/.claude/.credentials.json
sudo nixos-rebuild switch --flake .#khali
sudo systemctl restart hermes-agent
```

`hermes-agent-credentials.service` は「既存があれば上書きしない」ロジックなので、強制更新には working copy 削除が必要。

### コスト・呼び出し回数の集計

```bash
# 当日の delegate ログを抽出
journalctl -u hermes-agent --since today | grep "hermes.plugin.claude_code"

# 月次コスト概算
journalctl -u hermes-agent --since "1 month ago" \
  | grep -oP 'cost_usd=\K[0-9.]+' \
  | awk '{s+=$1} END {print s}'
```

### よくある障害と対処

| 症状 | 原因 | 対処 |
|---|---|---|
| `not authenticated` / `401` がログに出る | credentials.json が壊れている / 期限切れ / refresh token 衝突 | 上記「Credentials の更新フロー」を実施 |
| `claude binary not found on PATH` | `extraPackages` に `pkgs.claude-code` が無い、systemd PATH に追加されていない | `hermes-agent.nix` の `extraPackages` を確認、`systemctl show hermes-agent | grep Path` で実 PATH を見る |
| stream-json が壊れる / 結果が空 | `--include-partial-messages` `--verbose` 抜け、または model 側のエラー | `tools.py` の cmd args を確認、stderr_tail を読む |
| `claude_code` 呼び出しが timeout だらけ | task が大きすぎる / Opus が混雑 | `timeout_seconds` を 1800 まで上げる、または task を分割 |
| 結果に `Bash(rm:*) is not allowed` 等 | DISALLOWED_TOOLS で正しくブロック (期待動作) | task を書き換えて読み取り中心の指示にする |
| 再帰 delegate (claude_code 内で claude_code) | system_prompt 違反 + 物理ブロック発動 | system_prompt を見直し、本当に再帰したい場合のみ DISALLOWED_TOOLS から `Bash(claude:*)` を外す (非推奨) |

### Hermes 側 system prompt の運用方針

`agent.system_prompt_prefix` で claude_code の利用ガイドラインを明示している。実運用で「claude_code を使ってほしい / 使ってほしくない」のチューニングが必要になったら、ここを編集して `nixos-rebuild switch`。

## Future improvements / TODO

実装スコープ外で将来検討する項目。新規 idea が出たらここに追記し、plan ファイルには戻さない。

### 認証経路の代替

- **API key fallback**: OAuth 経路で運用が破綻したら (rate limit 枯渇 / 同時 session 制約 / refresh 衝突) Anthropic Console 発行の API key を `age.secrets."hermes-anthropic-key"` で配備し、`tools.py` の env 構築で `ANTHROPIC_API_KEY` を渡す経路を追加する。Pro/Max sub と別課金になる点に注意。
- **OAuth account dir の seed 拡張**: claude CLI のバージョンによっては `oauth_account/` のような追加 dir が必要になる可能性。現在は `.credentials.json` 1 ファイルだけ seed しているが、必要なら my-secrets 側を `tar.age` 形式に拡張する。

### 観測性・ガードレール

- **日次コスト cap**: `post_tool_call` hook で当日の累積コストを SQLite に記録し、threshold を超えたら以降の呼び出しでエラー文字列を返す
- **delegate 回数ダッシュボード**: Grafana なり SigNoz なりに journalctl の構造化ログを取り込んで可視化
- **遅延中央値 / p95 のメトリクス化**: `elapsed_ms` を histogram に

### 機能拡張

- **逆方向 delegate (Claude Code → Hermes)**: 現状は Hermes → Claude Code の片方向。Claude Code 側から Hermes を呼ぶ設計の必要性は要件発生時に再検討
- **Phase 3 SmolVM サンドボックス連携**: `terminal.backend = "smolvm"` への移行 (`docs/hermes-agent-phase3-smolvm.md` 参照)。claude_code subprocess も SmolVM 内に閉じ込めるか、ホスト直で残すかを決める
- **Codex CLI ⇄ Hermes との統合**: `home-manager/narinari/features/llm/codex.nix` の Codex 経路と統合してマルチプロバイダー delegate にする可能性

### 設計代替路線 (採用せず、参考)

- **`claude mcp serve` / `steipete/claude-code-mcp` 経由**: 標準 MCP server として expose するパターン。今回採用せずプラグイン直書きにした理由は計画書 (`~/.claude/plans/hermes-agent-claude-code-...md`) の Context 節を参照。Hermes plugin に過度な複雑性が出てきたら再評価する
- **`claude` を long-running daemon として起動 + 都度 stdin/stdout で会話継続**: 今回は `claude --print -p` の都度起動方式。session 継続は `--resume` フラグで対応。長期セッションを使う運用が固まれば daemon 化も検討
