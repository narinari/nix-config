# Claude Code ⇄ codex CLI Bridge (`codex-implement` skill)

khali / hail-mary ホスト (narinari user, home-manager 管理) で動いている **Claude Code (Opus 4.7)** から、**設計済みの実装タスク** を手元の **codex CLI** に委譲し、生成された diff を Claude 自身がレビューして取り込む仕組み。

実装の中核は Claude Code の `~/.claude/skills/codex-implement/SKILL.md`。SKILL 本文に「設計 → codex 委譲 → レビュー」のワークフローを書き、Bash 経由で `codex exec --json --profile local_qwen3_8_coding ...` を呼ぶ。

関連ドキュメント:
- 逆方向 (Hermes Agent → Claude Code Opus) のブリッジ: [`hermes-agent-claude-code-bridge.md`](./hermes-agent-claude-code-bridge.md)
- 計画ドキュメント: `~/.claude/plans/codex-cli-hail-mary-ollama-qwen3-6-35b-a-precious-globe.md`

## アーキテクチャ

```
narinari (claude code session)
    │
    │ Skill: codex-implement (~/.claude/skills/codex-implement/SKILL.md)
    │
    ▼ Bash tool: codex exec --json --profile local_qwen3_8_coding -C <repo> "<spec>"
codex-cli (narinari user, $HOME/.codex/*.config.toml)
    │
    │ HTTP: http://ai/v1 (wire_api = "responses")
    ▼
Tailscale Aperture (Tailscale identity 認証, ダミー API key)
    │
    ▼
hail-mary (Ollama, qwen3.8:27b-mxfp8 on MLX backend)
```

実装場所:
- SKILL 本文 (source-of-truth): [`home-manager/narinari/features/llm/claude/skills/codex-implement/SKILL.md`](../home-manager/narinari/features/llm/claude/skills/codex-implement/SKILL.md)
- 配備 nix module: [`home-manager/narinari/features/llm/claude-code-skills.nix`](../home-manager/narinari/features/llm/claude-code-skills.nix)
- codex 側 config: [`home-manager/narinari/features/llm/codex.nix`](../home-manager/narinari/features/llm/codex.nix)
- imports 起点: `home-manager/narinari/khali.nix`, `home-manager/narinari/hail-mary.nix`

## ワークフロー (Skill 内部)

Skill 内に明示されている 3 フェーズ:

| Phase | 担当 | 内容 |
|---|---|---|
| 1. Design | Claude | Goal / Constraints / Interfaces / Acceptance / Out of scope を spec として書き出す。不明点は `AskUserQuestion` で確認 |
| 2. Delegate | codex | `codex exec --json --profile local_qwen3_8_coding -C <repo> --sandbox workspace-write ...` で 1 回だけ実行 |
| 3. Review | Claude | `git diff` + 7 項目の routine check (out-of-scope edits / type drift / test coverage / error handling / secret leakage / cross-platform / commit-message comments) |

## 使い方

Claude Code セッションで以下のように指示すれば SKILL が auto-trigger する:

> 「`codex-implement` を使って `<repo>` に `<feature>` を実装してほしい。Acceptance: `<test command>`。Out of scope: `<files NOT to touch>`」

明示呼び出しは `Skill` ツールで `codex-implement` を指定する。

## 設定の所在

| 役割 | ファイル |
|---|---|
| codex CLI パッケージと `~/.codex/config.toml` + profile ファイル群 | `home-manager/narinari/features/llm/codex.nix` |
| Aperture 環境変数 (`OPENAI_BASE_URL=http://ai/v1` 等) | `home-manager/narinari/features/llm/aperture.nix` |
| Claude Code 本体と `~/.claude/settings.json` | `home-manager/narinari/features/llm/default.nix` |
| SKILL 配備 activation | `home-manager/narinari/features/llm/claude-code-skills.nix` |
| SKILL 本文 | `home-manager/narinari/features/llm/claude/skills/codex-implement/SKILL.md` |
| `Bash(codex:*)` permission allow | `home-manager/narinari/features/llm/default.nix` の `permissions.allow` |

## セットアップ手順

### 1. hail-mary 側でモデル tag を pull

khali / hail-mary 上の Claude / codex は aperture (`http://ai/v1`) 経由で Ollama を叩く。モデル本体は hail-mary に存在する必要がある:

```bash
# hail-mary 側で
ollama pull qwen3.8:27b-mxfp8
ollama list | grep qwen3.8
```

### 2. nix-config を適用

```bash
cd /home/narinari/nix-config
home-manager build --flake .#narinari@khali       # eval だけ先に
home-manager switch --flake .#narinari@khali

# hail-mary 側でも同じ
# home-manager switch --flake .#narinari@hail-mary
```

### 3. 反映確認

```bash
# codex 側
grep '^model = ' ~/.codex/config.toml             # qwen3.8:27b-mxfp8 になる
cat ~/.codex/local_qwen3_8_coding.config.toml    # profile は独立ファイル (下記参照)
! grep -q '^\[profiles\.' ~/.codex/config.toml && echo "OK: legacy profile テーブルなし"

# SKILL 側
head -10 ~/.claude/skills/codex-implement/SKILL.md
```

### 4. Aperture でモデルが見えるか

```bash
curl -s http://ai/v1/models | jq -r '.data[].id' | grep -i qwen3.8
```

出ない場合は手順 1 の `ollama pull` をやり直す。

### 5. codex headless smoke

```bash
# (a) read-only での返答テキスト確認
codex exec --json --profile local_qwen3_8_coding --sandbox read-only --skip-git-repo-check \
  -C /tmp "Say hi in Japanese in one short sentence." | tail -20

# (b) workspace-write で 1 ファイル作成
mkdir -p /tmp/codex-smoke && cd /tmp/codex-smoke && git init -q
codex exec --profile local_qwen3_8_coding --sandbox workspace-write \
  -C /tmp/codex-smoke --output-last-message /tmp/codex-last.md \
  "Create a file called hello.txt containing exactly the line: hello from qwen"
cat hello.txt   # → "hello from qwen"
```

### 6. Claude Code 内 E2E

1. 使い捨て git repo (`/tmp/codex-skill-e2e`) を作って `claude` から開く。
2. プロンプト: 「`codex-implement` skill で `main.py` に `def add(a: int, b: int) -> int` を実装し、`tests/test_add.py` を pytest 形式で追加してほしい。Out of scope: `requirements.txt`。」
3. 期待:
   - Claude が Phase 1 spec を提示する
   - Bash で `codex exec --json --profile local_qwen3_8_coding -C /tmp/codex-skill-e2e ...` を実行
   - `main.py` + `tests/test_add.py` だけが変更される
   - Claude が Phase 3 review を返し `pytest` 実行可否に言及

## 運用

### codex profile の使い分け

| profile | model | 用途 |
|---|---|---|
| (profile なし = base config) | `qwen3.8:27b-mxfp8` | `--profile` を省いたときのデフォルト |
| `local_qwen3_8_coding` | `qwen3.8:27b-mxfp8` | 実装委譲のメイン経路。`codex-implement` skill から呼ばれる |
| `local_gemma4` | `gemma4:26b-a4b-it-q8_0` | 汎用対話 / 指示追従重視 (速度優先) |

profile 切り替えは `codex --profile <name> ...` で都度指定。`~/.codex/config.toml` のトップレベル `model = ...` を書き換えるとデフォルトが変わる。

### profile は独立ファイル方式 (codex-cli 0.146 以降)

codex-cli 0.146 で profile の仕組みが **CONFIG_PROFILE_V2** に変わった。`--profile <name>` は
`$CODEX_HOME/<name>.config.toml` を base config (`config.toml`) の上に **レイヤー** する。

そのため `config.toml` に旧来の `[profiles.<name>]` テーブルを残したまま `--profile <name>` を
使うと、次のエラーで失敗する:

```
Error loading config.toml: --profile `<name>` cannot be used while ~/.codex/config.toml
contains legacy `profile = "<name>"` or `[profiles.<name>]` config; move those settings into
~/.codex/<name>.config.toml and remove the legacy profile selector/table.
```

> **重要**: このとき codex は **exit code 0 を返す**。呼び出し側 (Claude の Bash tool 等) からは
> 成功に見えて 1 ファイルも変更されない silent failure になるので、diff が空のときは
> stdout にこのエラーが出ていないか必ず確認すること。

profile を足すときは `home-manager/narinari/features/llm/codex.nix` の `codexFiles` に
`"<name>.config.toml" = mkProfile "<model>";` を追加する。`config.toml` 側には書かない。

> **注**: 存在しない profile 名を渡してもエラーにならず、黙って base config だけで動く。
> profile 名の typo は検出されないので注意。

### Hermes 経路との関係

Hermes Agent は逆方向 (`services.hermes-agent` → Claude Opus, hermes user) で動作する。本ドキュメントの経路は narinari user の対話セッション → 手元 codex (local qwen3.8) で、user / service / 認証経路がすべて分かれているため衝突しない。

将来 Hermes 経路と統合してマルチプロバイダー delegate にする構想は `hermes-agent-claude-code-bridge.md` の Future improvements 節に置いてある。

### よくある障害と対処

| 症状 | 原因 | 対処 |
|---|---|---|
| `codex: error: connection refused` to `http://ai/v1` | aperture が落ちている / tailnet 外 | Tailscale 状況を確認、Claude には fallback せず素直に報告させる |
| `model not found: qwen3.8:27b-mxfp8` | hail-mary 側で tag 未 pull | セットアップ手順 1 を再実行 / `--profile local_gemma4` で暫定運用 |
| `--profile <name> cannot be used while ... contains legacy [profiles.<name>]` (かつ exit 0) | `config.toml` に旧形式の `[profiles.*]` が残っている | 「profile は独立ファイル方式」節を参照。`codex.nix` の `codexFiles` に profile を移す |
| codex hangs 5 min 超 | 初回ロード / context 過大 | `timeout 300 codex exec ...` で wrap、spec を縮めて再投入 |
| `--json` が空 / 非 JSON 出力 | codex-cli が 0.130 未満 | `codex --version` 確認、`inputs.codex-cli-nix` 更新 |
| diff 0 行 | 実は `read-only` sandbox / `-C` ミス / profile エラーの silent failure | `--sandbox workspace-write` と repo root を再確認。stdout に `Error loading config.toml` が出ていないかも見る |
| codex がインデント調整に延々と時間を使う | spec に整形の指示が入っている | pre-commit で `nixfmt` 等が走るなら「整形は評価対象外」と spec に明記する |
| spec 外のファイルが変わる | spec の制約が曖昧 | `git checkout --` で revert、明示的に「`X` は触らない」を spec に追加して再委譲 |

## Future improvements

実装スコープ外。新規 idea が出たらここに追記し、plan ファイルには戻さない。

### Skill 拡張

- **`--output-schema` の活用**: codex の最終応答を JSON Schema で縛り、Claude 側の review で `jq` ベースの自動チェックを掛ける
- **`codex exec review` の二段化**: 自前 review に加えて中間で `codex exec review` を挟む案。コスト増と引き換えに style 系を local で潰せる
- **`scripts/` への外出し**: SKILL 内の Bash one-liner を `home-manager/narinari/features/llm/claude/skills/codex-implement/scripts/` 配下のスクリプトに切り出し、SKILL 本文を簡素化

### モデル選択の自動化

- aperture `/v1/models` を skill 内で叩いて、`qwen3.8` が無ければ `gemma4` に自動フォールバック
- task サイズに応じた `gemma4` (small) / `qwen3_8_coding` (large) の routing

### Hermes 経路との統合

- Hermes 側 `services.hermes-agent` の `Codex CLI ⇄ Hermes との統合` TODO と接続。Hermes から `codex_exec` tool を expose してマルチプロバイダー delegate を完成させる構想

### 観測性

- codex `--json` stream を SQLite に記録し、当日 delegation 回数 / 累積秒数を可視化
- SKILL invocation 回数を `~/.claude/cost-tracker.log` 由来で集計し、Hermes 側 journalctl 集計と対比
