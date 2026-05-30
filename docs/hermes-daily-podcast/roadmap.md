# hermes-daily-podcast ロードマップ

Phase 1 (現状) は `pkgs/hermes-daily-podcast-plugin/` で実装済み:
HN / はてブ (タグ検索) / Reddit / Bluesky を巡回 → LLM (qwen3.6:35b-mlx via aperture)
で採点 → 日本語要約 → VOICEVOX (四国めたん ノーマル) で音声化 →
Tailscale 内 nginx で podcast 配信。定期実行は Hermes 内蔵 cron。

このドキュメントは Phase 2 以降の改善候補をまとめる。優先度は仮置き。

## Phase 2

### Discord deliver で生成結果を通知 ★ 推奨

Hermes 内蔵 cron は `--deliver discord` フラグで実行結果を Discord channel に
ポストできる。現状の cron job (`hermes-daily-podcast-default`) は deliver なしで
登録されているため、結果は journalctl にしか残らない。

実装:

```bash
sudo -u hermes hermes cron edit hermes-daily-podcast-default --deliver discord
```

または初回 seed (`hosts/khali/podcast-timer.nix:hermes-daily-podcast-seed`) で
`--deliver discord` 付きで登録する形に変える。

うまくいけば「22:00 になると Discord に『hobby-models と ai-tips の今日の episode が
できました。audio_url: ...』と通知が来る」というフローになる。

留意点:

- Discord に流れる量が多すぎる場合は `generate_all_today_episodes` の戻り値を
  小さく整形する handler 側修正が必要 (現状は summary + results をフル返却)。
- 失敗時のみ通知する設計にしたい場合は cron job を 2 つに分ける案もある:
  1 つは silent、1 つはエラー時のみ Discord 通知。

### 二人対談形式 (NotebookLM 風)

- `compose_script` を「ホスト + コメンテーター」のターン制御台本に拡張
- `synthesize_script` の `role_speakers` を `{"host": 2, "commentator": 3}` のように
  渡せるよう topic config に `role_speakers` field を追加
- 台本生成プロンプトを「Q&A 風 / 掛け合い」スタイルに

### Tailscale Funnel で公開

- Overcast / Pocket Casts (中央 crawler 型 podcast app) を使いたい場合に必要
- `tailscale funnel 443 on` + nginx HTTPS vhost で `*.taild10c60.ts.net` で公開
- TLS 証明書は Tailscale 自動発行
- feed と mp3 が URL を知っている人なら誰でも視聴可能になる点に注意
- Apple Podcasts ディレクトリ登録もこの段階で可能

### Reddit OAuth (`asyncpraw`) 化

- anonymous JSON は 2026 年現在 401 で失敗するケースが多い
- Reddit app を作って client_id / client_secret を取得 → agenix で
  `daily-podcast-env.age` に追加
- `sources/reddit.py` を asyncpraw 経由に切り替え (Phase 1 は anonymous fallback を残す)
- レート制限が 10 req/min → 60 req/min に緩和

### Bluesky を有効化

- `BLUESKY_HANDLE` / `BLUESKY_APP_PASSWORD` を agenix `daily-podcast-env.age` に追加
- hermes-agent.nix の `environmentFiles` に追加
- atproto Python パッケージを `services.hermes-agent.package.override` で注入する必要あり

## Phase 3

### Hermes runtime に正規 Python deps を注入

- 現状 `feedgen` / `feedparser` / `trafilatura` / `rapidfuzz` / `url-normalize` /
  `atproto` は hermes-agent runtime に無く、plugin 側 stdlib fallback でしのいでいる
- `services.hermes-agent.package = pkgs.hermes-agent.override { extraPythonPackages = [...]; }`
  でクリーンに注入できる (hermes-agent nix module の `extraPythonPackages` API 確認済み)
- 効果: RSS 生成が完全な iTunes ext + Podcast 2.0 仕様、要約精度向上、dedup 精度向上

### 評価フィードバックループ

- LLM の自己採点 (生成した episode 自体をもう一度 LLM に渡して「ホビー模型
  ジャンルとして適切だったか」を点検)
- Discord で 👍 / 👎 リアクションを集計して次回 score の prior に使う
- 重複検出を sentence-transformers の embedding cosine に置き換え

### AivisSpeech 移行検討

- Style-Bert-VITS2 ベースの感情表現に強い TTS
- VOICEVOX engine 互換 API を提供 (URL prefix を差し替えるだけで使える)
- 2026 Q2 以降の成熟・利用規約整備を待ってから検討

### X (Twitter) ソース対応

- X API v2 Basic ($200/月) が必要なので scope outside だった
- RSSHub セルフホストや、コミュニティ X gateway が現実解になるか継続観察

### Podcast 2.0 value tag (リスナーから micropayment)

- iTunes 互換 RSS は維持しつつ podcast namespace の `<podcast:value>` を追加
- リスナー規模が増えた時の monetization 選択肢

## 参考: 設計の主要判断 (Phase 1 で決定済み)

- VOICEVOX engine は公式 Docker (`virtualisation.oci-containers`) で運用。nixpkgs
  パッケージはモジュール化未成熟、Docker の方が更新頻度・対応プラットフォームで優位
- LLM 採点 + 要約は `qwen3.6:35b-mlx` (aperture 経由 hail-mary Ollama)。
  hermes-agent default model と同じ
- 定期実行は Hermes 内蔵 cron (`hermes cron`)。systemd timer ではなく Discord 経由で
  動的に管理可能
- トピック追加は `add_topic` ツール経由で `/var/lib/hermes-podcast/topics.toml` に
  append。nixos-rebuild 不要、翌日の cron で自動的に拾われる
- 配信先は Phase 1 では Tailscale 内 nginx (`http://khali.taild10c60.ts.net/podcasts/`)。
  Apple Podcasts (iOS 純正) は client-side fetch なので Tailscale 内 feed でも動作する
