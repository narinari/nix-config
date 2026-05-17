# hermes-family-inventory-plugin

Hermes Agent プラグイン。家族向け在庫管理サービス [family-inventory](https://github.com/narinari/family-inventory) の Agent API
(REST + `X-API-Key` / `X-Agent-Actor`) を OpenAPI 駆動で Hermes ツールとして公開する薄いブリッジ。

## 設計方針

- **ドメイン知識ゼロ**: アイテム種別 / 業務ルール / ステータス遷移などの仕様は family-inventory リポジトリ側 (および同梱 `openapi.yaml`) が単一情報源。本 plugin はあくまで「OpenAPI を読んで HTTP を叩く」薄い層。
- **動的登録**: `src/__init__.py:register()` がプラグインロード時に `openapi.yaml` をパースし、`operationId` ごとに `ctx.register_tool(...)` を呼ぶ。tool の追加・削除・パラメータ変更はすべて `openapi.yaml` の差し替えだけで反映される。
- **OAuth ではなく API キー**: family-inventory が発行するエージェント用 API キー (`X-API-Key`) と Actor ID (`X-Agent-Actor`) を env 経由で受け取る。

## 必要な環境変数

| 変数 | 説明 |
| --- | --- |
| `FAMILY_INVENTORY_API_URL` | API サーバ base URL (例: `https://family-inventory.tail.example.ts.net`)。末尾スラッシュは付けても付けなくても可。 |
| `FAMILY_INVENTORY_AGENT_API_KEY` | family-inventory が発行したエージェント API キー。`X-API-Key` ヘッダにそのまま入る。 |
| `FAMILY_INVENTORY_AGENT_ACTOR` | エージェント Actor ID。family / user 紐付けに使う。 |

3 つのうち 1 つでも欠けていると、全ての tool 呼び出しが構成エラーを返す (プラグイン自体のロードは止めない)。

## openapi.yaml の同期

family-inventory リポジトリ側で OpenAPI 仕様が更新されたら、以下のいずれかで同期する。

```bash
# 既定パス: ~/dev/src/github.com/narinari/family-inventory/apps/api/openapi.yaml
./update-openapi.sh

# 明示パス
./update-openapi.sh /path/to/openapi.yaml

# 単純な cp でも同じ
cp /home/narinari/dev/src/github.com/narinari/family-inventory/apps/api/openapi.yaml \
   ./src/openapi.yaml
```

同期後は plugin (および Hermes Agent ホスト) を rebuild する:

```bash
nix build --no-link --print-out-paths \
  .#packages.x86_64-linux.hermes-family-inventory-plugin

# 本番反映 (khali 上の Hermes Agent サービス)
sudo nixos-rebuild switch --flake .#khali
```

## 動作確認 (khali)

```bash
# Plugin が読み込めているか
journalctl -u hermes-agent -b --no-pager | grep -i family-inventory

# ツール一覧
hermes tools list | grep -i family

# 実呼び出し (例: 所有中アイテム一覧)
hermes -p 'listItems を status=owned で呼んで結果を要約して'
```

## khali host への統合手順

`hosts/khali/hermes-agent.nix` には plugin の宣言・toolset への追加・非機密 env
(`FAMILY_INVENTORY_API_URL`, `FAMILY_INVENTORY_AGENT_ACTOR`) が既に組み込まれている
が、`FAMILY_INVENTORY_AGENT_API_KEY` を渡すための agenix secret 関連はコメントアウト
状態。以下の順序でユーザーが対話的に作業すること。

### 1. Agent API キーを生成

```bash
openssl rand -hex 32
```

生成した値を安全な場所 (1Password 等) に控える。

### 2. Cloud Run 側に同じ値を投入

family-inventory リポジトリの `docs/AGENT_DEPLOYMENT.md` に従い、Cloud Run の
`AGENT_API_KEY` (Secret Manager) として上記の値を登録する。

### 3. agenix で secret ファイルを作成

このリポジトリ (nix-config) ではなく、`inputs.my-secrets` の実体である
`nix-secrets` リポジトリ側で agenix を実行する。

```bash
# my-secrets リポジトリの clone (場所はユーザー環境による)
cd /path/to/nix-secrets
agenix -e private/family-inventory-agent-env.age
# エディタが開いたら以下を 1 行で書いて保存:
# FAMILY_INVENTORY_AGENT_API_KEY=<手順 1 で生成した値>

git add private/family-inventory-agent-env.age
git commit -m "feat: add family-inventory agent API key"
git push
```

その後、nix-config 側で flake input を更新:

```bash
cd /home/narinari/nix-config
nix flake lock --update-input infra/my-secrets --update-input workstations/my-secrets
# ↑ 入力名は flake.lock の構造による。`nix flake metadata` で確認できる。
# 単純化するなら `nix flake update` でも良いが影響範囲が広がる。
```

### 4. `hosts/khali/hermes-agent.nix` のコメントアウト解除

以下 2 箇所の `#` を外す:

- `age.secrets."family-inventory-agent-env" = { ... };` ブロック
- `services.hermes-agent.environmentFiles` 内の
  `config.age.secrets."family-inventory-agent-env".path`

### 5. `FAMILY_INVENTORY_API_URL` を実 URL に置換

`environment.FAMILY_INVENTORY_API_URL` の placeholder
(`https://CHANGE_ME_CLOUD_RUN_URL`) を実際の Cloud Run URL に置換する。

### 6. rebuild

```bash
cd /home/narinari/nix-config

# まず評価エラーがないかドライラン
sudo nixos-rebuild build --flake .#khali

# 問題なければ反映
sudo nixos-rebuild switch --flake .#khali

# Plugin がロードできたか確認
journalctl -u hermes-agent -f | grep -i family-inventory
```

### 7. 動作確認

hermes CLI から自然言語で呼び出し、`listItems` 等の tool が叩かれることを
確認する。

```bash
hermes -p '家の持ち物を見せて (listItems を status=owned で呼んで)'
```

`401 Unauthorized` が返る場合は API キーが Cloud Run 側と一致していない。
`missing env vars` エラーが出る場合は手順 4 のコメントアウト解除を漏らしている。

## ファイルレイアウト

```
hermes-family-inventory-plugin/
├── default.nix              # Nix derivation (runCommand で src/ を $out/ にコピー)
├── README.md                # 本ファイル
├── update-openapi.sh        # openapi.yaml 同期スクリプト
└── src/
    ├── plugin.yaml          # Hermes plugin manifest
    ├── openapi.yaml         # family-inventory から同期した OpenAPI 仕様
    ├── __init__.py          # register() エントリポイント (OpenAPI → ctx.register_tool)
    └── http.py              # HTTP クライアント (httpx / urllib fallback)
```

## トラブルシューティング

| 症状 | 確認ポイント |
| --- | --- |
| Hermes 起動時に `family-inventory: failed to load openapi.yaml` | `src/openapi.yaml` の YAML 構文。Hermes Python env に PyYAML が無ければ JSON フォールバックは効くが、family-inventory の生成出力は YAML 形式。 |
| Tool が一つも登録されない | `journalctl -u hermes-agent` で `registered 0 tools` を確認。`paths` が空でないか / `operationId` が全 operation に付いているかをチェック。 |
| 全ツールが `missing env vars` エラー | systemd unit / `environmentFiles` で env を渡せているか確認。`systemctl show hermes-agent -p Environment` で実際の値を見られる。 |
| 401 / 403 が返る | API キーの失効 / Actor ID と family の紐付け (`agentMappings`) を family-inventory 側で確認。 |
