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
