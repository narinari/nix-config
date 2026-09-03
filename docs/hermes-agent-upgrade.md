# hermes-agent のアップグレード手順

khali の `services.hermes-agent` は上流 NousResearch/hermes-agent を flake input として [`workstations/flake.nix`](../workstations/flake.nix) で tag ピンして使っている。この doc はそのバージョンを上げる手順。

関連:
- [`hosts/khali/hermes-agent.nix`](../hosts/khali/hermes-agent.nix) (サービス定義)
- [`hosts/khali/podcast-timer.nix`](../hosts/khali/podcast-timer.nix) (内蔵 cron 登録)

## なぜ 2 段階 relock が要るか

`hermes-agent` input は root の `flake.nix` ではなく `workstations/flake.nix` で宣言されている。root の `flake.lock` では `workstations` ノード配下にネストして記録されるため、`workstations/` を relock しただけでは root 側の lock が古いままになる。必ず 2 段階で行う。

## 手順

1. **state をバックアップ** (必須)

    ```
    sudo systemctl stop hermes-agent
    sudo tar -czf /var/lib/hermes-backup-$(date +%Y%m%d).tar.gz -C /var/lib hermes
    ```

    理由: v0.19.0 でセッションメタデータが `state.db` に統合され、v0.20.0 で compact v23 FTS レイアウトと fail-closed な CJK-bigram マイグレーションが入る。日本語運用なので直撃する。`/var/lib/hermes-podcast` は生成物なのでバックアップ不要。

2. **tag を書き換え** — `workstations/flake.nix` の `hermes-agent.url` の `refs/tags/<version>` を変更。

3. **2 段階 relock**

    ```
    cd workstations && nix flake update hermes-agent
    cd .. && nix flake update workstations
    ```

4. **ビルド確認 → 適用**

    ```
    nixos-rebuild build --flake ./workstations#khali
    nixos-rebuild switch --flake ./workstations#khali
    ```

    上流の `packages.default` は `full` variant (`extraDependencyGroups` に messaging / voice / tts-premium 等を含む) なので、初回ビルドは時間がかかる。先に `build` で通してから `switch` する。

5. **動作確認**

    ```
    hermes version
    systemctl status hermes-agent
    journalctl -u hermes-agent -n 200
    hermes doctor
    hermes plugins list
    hermes cron list
    ```

    `hermes doctor` は未知の root config キーと deprecated キーを報告する (v0.19.0 で追加)。`hermes plugins list` でローカル plugin 3 本 (claude-code / family-inventory / daily-podcast) が register されているか確認する。register されていなければ `services.hermes-agent.environment.HERMES_PLUGINS_DEBUG = "1"` を一時的に足して discovery ログを出す。

6. **ロールバック**

    flake.lock の `hermes-agent` ノードを戻して rebuild。state.db がマイグレーション済みで戻せない場合:

    ```
    sudo systemctl stop hermes-agent
    sudo rm -rf /var/lib/hermes
    sudo tar -xzf /var/lib/hermes-backup-<date>.tar.gz -C /var/lib
    ```

## アップグレードで自動的に変わるもの

v2026.5.7 → v2026.8.31 で NixOS module が生成する成果物のうち変わるのは以下の 4 点だけ (module option の削除・rename はゼロ):

| 対象 | 変化 | 理由 |
|---|---|---|
| `.hermes/config.yaml` の mode | `0640` → `0660` | `addToSystemPackages = true` のとき group 書き込み可にする挙動が入った |
| `.hermes/config.yaml` の中身 | `terminal.cwd` が自動注入される | 既存の `terminal.backend` / `timeout` は recursiveUpdate で保持される |
| systemd unit の env | `MESSAGING_CWD` が削除 | 上の `terminal.cwd` で代替 |
| `.hermes/.managed` | 空 → `nixos` | managedSystem 識別子が書かれるようになった |

## 維持すべきワークアラウンド

上流に解消の記載がないため削除してはいけないもの:

| 設定 | 場所 | 目的 |
|---|---|---|
| `browser.cdp_url = ""` | `settings` | `hermes setup` が書き込む死んだ CDP URL を deep_merge で打ち消し local mode を強制 |
| `skills.disabled` の claude-code 系 3 件 | `settings` | bundled skill の旧仕様 (`terminal` で `claude -p` を呼べ) と plugin 経路の競合回避 |
| `HERMES_STREAM_STALE_TIMEOUT = "1800"` | `environment` | `http://ai/v1` が MagicDNS 短縮名で local 判定されず、stream 側の既定 180s で自切断するのを防ぐ |
| `AGENT_BROWSER_EXECUTABLE_PATH` | `hermesEnvFile` | Playwright が DL する Chromium は Nix sandbox で動かないため Nix store の chromium を指す |

## 上げた直後に確認する挙動リスク

| リスク | 導入バージョン | 確認方法 |
|---|---|---|
| 保護ファイル (AGENTS.md / skills / memory) への書き込みが常に承認必須になり、無人 cron が承認待ちで止まる可能性 | v0.21.0 | Discord 経由で会話させ memory 保存が固まらないか見る |
| smart approvals が既定に変更。`terminal.backend = "local"` でホスト直接実行しているため直撃 | v0.19.0 | `terminal` ツールを 1 回実行させ承認フローを見る |
| cron が provider drift で fail closed になる。`podcast-timer.nix` の `hermes cron create` は provider を pin していない | v0.18.0 | `hermes cron list` と翌朝の episode 生成を確認 |
| cron job storage が per-profile に revert。既存 job のパスが移動している可能性 | v0.18.0 | 同上。消えていれば冪等 seed が再登録する |
| subprocess の PYTHONHOME/PYTHONPATH 隔離により daily-podcast が呼ぶ `yt-dlp` が壊れる可能性 | v0.20.2 | `generate_daily_episode` を手動実行し youtube source を通す |
| iteration limit の既定が 90 → 500 (v0.20.0)、さらに 250 iterations (v0.21.0) に変わり 1 ターンが長時間化しうる | v0.20.0 / v0.21.0 | `providers.aperture.request_timeout_seconds = 1800` で足りるか実測 |
| custom-endpoint probe が 1.5s 上限になり、cold 時の `http://ai/v1` が model picker に出ない可能性 (推論本体には無関係) | v0.20.0 | `hermes model` の一覧に aperture のモデルが出るか |

## バージョン履歴

| 日付 | 変更 |
|---|---|
| 2026-05-09 | v2026.5.7 (v0.13.0) にピン |
| 2026-09-03 | v2026.8.31 (v0.21.0) へ更新 |
