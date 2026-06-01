# hermes-daily-podcast ロードマップ

Phase 1 (現状) は `pkgs/hermes-daily-podcast-plugin/` で実装済み:
HN / はてブ (タグ検索) / Reddit / Bluesky を巡回 → LLM (qwen3.6:35b-mlx via aperture)
で採点 → 日本語要約 → VOICEVOX (四国めたん ノーマル) で音声化 →
Tailscale 内 nginx で podcast 配信。定期実行は Hermes 内蔵 cron。

このドキュメントは Phase 2 以降の改善候補をまとめる。優先度は仮置き。

## Phase 1.5 (完了)

shi3z 氏の [siki](https://github.com/shi3z/siki) (式神 — ローカル agentic AI)
を参考に取り込んだ短期改善 2 件。実装済み。

### 多段モデル化 (score: 軽量 / summarize: 35B) ★★★ — 完了

`qwen3.6:35b-mlx` 一本だった LLM 呼び出しを 2 段に分離。

- score (採点): `qwen3.5:4b-mlx` (hail-mary に pull 済み)。候補 30-60 件を
  一括で裁くだけなので 4B で十分
- summarize (要約・翻訳): `qwen3.6:35b-mlx` 維持

実装:

- `src/config.py` に `score_model()` / `summarize_model()` を追加。
  既存 `llm_model()` は summarize の alias として後方互換
- `src/score.py` / `src/summarize.py` がそれぞれ `cfg.score_model()` /
  `cfg.summarize_model()` を `llm.chat_json` の `model` 引数に渡す
- 環境変数 (`hosts/khali/hermes-agent.nix` で配備):
  - `HERMES_DAILY_PODCAST_SCORE_MODEL` (default: `qwen3.5:4b-mlx`)
  - `HERMES_DAILY_PODCAST_SUMMARIZE_MODEL` (default: `qwen3.6:35b-mlx`)
  - 既存 `HERMES_DAILY_PODCAST_LLM_MODEL` は両者未設定時の fallback として残す

期待効果: スループット 3-5 倍、hail-mary 占有時間が短く Hermes 他処理にも余裕。

### 採点を HIGH/MID/LOW の離散ラベル化 ★★ — 完了

`src/score.py` のプロンプトを 0-10 float → HIGH/MID/LOW + reason に変更。
内部表現は `score: float` を維持し、LLM 出力ラベルを 10/5/1 にマッピング。
既存 `MIN_SELECTION_SCORE=3.0` フロアロジックと `select_top` の挙動は不変。

- 旧 prompt が float を返す場合に備えて legacy 互換パスを `_decide_score()`
  に残してある (label が無く `score` だけ来たらそのまま採用)
- 単体テストは `tests/test_score.py` (ラベルマッピング / 軽量モデル使用 /
  legacy float 互換 / フロアカット を網羅)

期待効果: 採点ブレ減、低品質候補のフロアカット精度向上。

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

### siki 由来の中期アイデア (画像生成 / Twitter curation)

- **エピソード毎の cover image 自動生成** — siki は FLUX.2 / Helios を
  tool として持つ。podcast の `<itunes:image>` を毎エピソード固有
  (今日のトピックに合わせた cover) にすれば Apple Podcasts の見栄えが
  化ける。ただし hail-mary GPU を相当食うので、まずは静的 cover を維持。
  実装するなら trigger 後の非同期生成 (mp3 配信を block しない) が前提。
- **Twitter (X) curation の手法** — siki は「Twitter timeline curation
  with LLM filtering」を実装している。X 公式 API は有料 ($200/月) なので、
  shi3z 氏がどう取っているか (login session の cookie 経由か、個人 API tier
  か) を確認してから判断する。本家方式が取り込めれば Phase 2 で外したまま
  になっている X 連携が復活する。

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
