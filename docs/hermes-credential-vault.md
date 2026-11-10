# Hermes の Web ログイン用シークレット管理 (Bitwarden エージェントアカウント)

khali の Hermes に Web サービスへのログインを任せるための認証情報の扱い。
**正本は narinari の Bitwarden vault だけ** で、サイトごとのシークレットは複製しない。

## 構成

```
narinari の vault ──(Families org の collection `hermes-agent`)──▶ エージェント専用アカウント (無料)
                                                                     │ bw CLI (hermes ユーザー)
                                                                     ▼
                                     hermes plugin (bw.py) / 将来: browser_vault
```

- エージェントに任せるログインだけを collection `hermes-agent` に置く。
  アイテムの実体は 1 つなので、自分の vault からも普通に見えて編集できる。
- エージェントアカウントには collection の閲覧権限 (パスワード閲覧可) だけを与える。
- vault 外に置く秘密情報はエージェントアカウントの鍵だけで、agenix で管理する:

| agenix secret | 中身 | 所有 | 用途 |
|---|---|---|---|
| `private/hermes-bw-agent-env.age` | `BW_CLIENTID=…` / `BW_CLIENTSECRET=…` (エージェントアカウントの個人 API キー) | root 0400 | `hermes-bw-login.service` の EnvironmentFile のみ |
| `private/hermes-bw-password.age` | エージェントアカウントのマスターパスワード (1 行、末尾改行なし) | hermes 0400 | `HERMES_BW_PASSWORD_FILE` → `bw unlock --passwordfile` |

Nix 側は `hosts/khali/hermes-bitwarden.nix` に集約している
(`bitwarden-cli` を extraPackages に追加、`HERMES_BW_PASSWORD_FILE` を設定、`hermes-bw-login.service`)。

### 利用経路

| 経路 | 仕組み | 状態 |
|---|---|---|
| 定型ジョブ (`--no-agent` cron plugin) | plugin が `bw unlock` → `bw sync` → `bw get item <id>` で取得し、自前でフォームに入力。LLM は値を見ない | 稼働 (例: [goldpoint-meisai](hermes-goldpoint-meisai.md)) |
| アドホック依頼 (Discord / cron のエージェント実行) | Hermes v0.22+ の `browser_vault`。ページに直接入力し、モデルには `{filled_fields, origin}` だけ返る | 未着手。v0.23 への更新と、無人解錠パッチが必要 (下記) |

## セットアップ

1. **Bitwarden (Web vault)**
   1. Families org に collection `hermes-agent` を作る。
   2. エージェント専用アカウントを作り (無料プラン)、org に招待する。
      collection `hermes-agent` だけに **Can view** (パスワード閲覧可) を付与する。
   3. エージェントアカウントでログインし、**Settings → Security → Keys → View API key**
      から `client_id` / `client_secret` を控える。
   4. 任せるログインアイテムを collection `hermes-agent` に移動する。
      URI はログインページのオリジン (例 `https://secure.goldpoint.co.jp`) を入れておく。
2. **agenix** (`~/nix-secrets`。宛先は `secrets.nix` に登録済み)

   ```bash
   cd ~/nix-secrets
   agenix -e private/hermes-bw-agent-env.age   # BW_CLIENTID=user.xxxx / BW_CLIENTSECRET=xxxx
   agenix -e private/hermes-bw-password.age    # マスターパスワード 1 行
   git add secrets.nix private/hermes-bw-*.age && git commit -m "feat: add hermes bitwarden agent account" && git push
   cd ~/nix-config/workstations && nix flake update my-secrets
   cd ~/nix-config && nix flake update workstations   # トップ flake は workstations 経由で my-secrets を持つ
   ```

3. rebuild 後に確認する:

   ```bash
   systemctl status hermes-bw-login                         # 成功 (ログイン済みならスキップ)
   sudo -u hermes env HOME=/var/lib/hermes bw status | jq .status   # "locked" (= ログイン済み)
   ```

EU リージョンや self-hosted を使う場合は、ログイン前に
`sudo -u hermes env HOME=/var/lib/hermes bw config server <url>` を実行する。

## ローテーション

- **サイトのパスワード**: 自分の vault で普通に変更する。plugin は毎回 `bw sync` するので、次回実行から反映される。
- **エージェントアカウントのマスターパスワード**: Bitwarden で変更し、`agenix -e private/hermes-bw-password.age` → rebuild。
- **API キー**: Bitwarden で rotate し、`hermes-bw-agent-env.age` を更新する。
  `sudo -u hermes env HOME=/var/lib/hermes bw logout` → `systemctl restart hermes-bw-login`。
- **漏洩が疑われるとき**: org からエージェントアカウントを外す (または削除する)。個人 vault には影響しない。

## 残存リスク

- terminal ツールも同じ `hermes` uid で動くので、マスターパスワードファイルを読んで `bw` を直接叩けば平文を取得できる。
  プロンプトインジェクションで漏れうる範囲は **collection `hermes-agent` の中身** に限られる。
  銀行やメインの Google アカウントのような高価値アカウントと、その TOTP はこの collection に入れない。
- マスターパスワードは agenix で復号されてディスク (tmpfs `/run/agenix`) 上にある。

## browser_vault (フェーズ B) のメモ

- Hermes v0.22.0 で `browser_vault` が入った。現在固定しているのは v0.21.5。
- 組み込みの Bitwarden backend の解錠は、対話プロンプトしかない (`tools/browser_vault_tool.py` の `can_prompt_here()`)。
  そのため Discord や cron からは `unlock_unavailable` になる。
- 独自の login backend プラグインは、verified / official のカタログ品以外は登録を拒否される。
- 対応方針: `agent/vault_backends/bitwarden.py` に「`vault.bitwarden.password_file` があれば自動で解錠する」パッチを当てる。
  あわせて upstream にも提案する。
