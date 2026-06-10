# Hermes Agent (Nous Research) — Tailscale Aperture 経由で hail-mary Ollama を利用
#
# 設計:
#   - 推論バックエンドは hail-mary 上の Ollama (qwen3.6:35b-a3b-coding-mxfp8)
#   - 直接接続ではなく Tailscale Aperture (http://ai/v1) を経由
#     → 認証は Aperture が Tailscale identity で代行 (実 API キー不要)
#   - 既存 Codex CLI 構成 (home-manager/narinari/features/llm/codex.nix) と同経路
#   - browser ツールは agent-browser CLI が local Chromium を直接 spawn する
#     (browser.cdp_url を設定しない = local mode、AGENT_BROWSER_EXECUTABLE_PATH で
#      Nix の chromium を指定)
#
# テスト:
#   systemctl status hermes-agent
#   journalctl -u hermes-agent -f
#   hermes version
{
  pkgs,
  inputs,
  config,
  lib,
  ...
}:

let
  # agent-browser が spawn する local Chromium。
  # Playwright が DL する Chromium は Nix sandbox 下で動かないため、Nix store の
  # chromium バイナリを AGENT_BROWSER_EXECUTABLE_PATH 経由で渡す。
  inherit (pkgs) chromium;

  # Aperture は Tailscale identity で認証するため実 API キーは不要だが、
  # hermes-agent モジュールが environmentFiles を要求するためダミーを供給する。
  hermesEnvFile = pkgs.writeText "hermes-env" ''
    OPENAI_API_KEY=aperture-tailscale-identity
    GATEWAY_ALLOW_ALL_USERS=true

    DISCORD_ALLOWED_ROLES=1028883038228189185
    DISCORD_HOME_CHANNEL=1500767462637961246

    AGENT_BROWSER_EXECUTABLE_PATH=${chromium}/bin/chromium
  '';

  # Claude Code delegate plugin (pkgs/hermes-claude-code-plugin/)。
  # NixOS module の extraPlugins が ${stateDir}/.hermes/plugins/nix-managed-claude-code/
  # に symlink し、Hermes が plugin.yaml を発見して register() を呼ぶ。
  hermesClaudeCodePlugin = pkgs.callPackage ../../pkgs/hermes-claude-code-plugin { };

  # family-inventory API 連携 plugin (pkgs/hermes-family-inventory-plugin/)。
  # OpenAPI 駆動で family-inventory Agent API を Hermes ツールとして公開する。
  # ドメイン知識は openapi.yaml が単一情報源 (詳細は plugin の README.md)。
  hermesFamilyInventoryPlugin = pkgs.callPackage ../../pkgs/hermes-family-inventory-plugin { };

  # daily-podcast plugin (pkgs/hermes-daily-podcast-plugin/)。
  # 毎日トピック毎に HN / Bluesky / はてブ / Reddit を巡回して LLM 要約 → VOICEVOX 音声化
  # → /var/lib/hermes-podcast/episodes/<topic>/<date>.mp3 と RSS を更新する。
  # 配信は podcast-nginx.nix の vhost (Tailscale 内のみ)。
  hermesDailyPodcastPlugin = pkgs.callPackage ../../pkgs/hermes-daily-podcast-plugin { };

  # hermes user 用の Claude Code 設定。narinari の global `~/.claude/CLAUDE.md` 等と
  # 干渉しないよう CLAUDE_CONFIG_DIR=/var/lib/hermes/.claude で隔離した上で、
  # delegate 専用の絞り込んだ permissions を配備する。
  hermesClaudeSettings = pkgs.writeText "hermes-claude-settings.json" (
    builtins.toJSON {
      permissions = {
        defaultMode = "acceptEdits";
        allow = [
          "Read(**)"
          "Edit(**)"
          "Write(**)"
          "Glob(**)"
          "Grep(**)"
          "Bash(git log:*)"
          "Bash(git diff:*)"
          "Bash(git status:*)"
          "Bash(git show:*)"
          "Bash(rg:*)"
          "Bash(fd:*)"
        ];
        deny = [
          "Read(**/.env)"
          "Read(**/.env.*)"
          "Read(**/secrets/**)"
          "Bash(rm:*)"
          "Bash(curl:*)"
          "Bash(wget:*)"
          "Bash(sudo:*)"
          "Bash(systemctl:*)"
          "Bash(nix-env:*)"
          "Bash(claude:*)"
        ];
      };
      model = "claude-opus-4-7";
    }
  );
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  age.secrets = {
    "friday-hermes-env" = {
      file = "${inputs.my-secrets}/private/friday-hermes-env.age";
    };

    # Claude Code OAuth credentials (Pro/Max sub) の暗号化スナップショット。
    # /run/agenix/hermes-claude-credentials に root:root 0400 で配置される。
    # hermes-agent-credentials.service が初回のみ /var/lib/hermes/.claude/.credentials.json
    # に hermes 所有でコピーする (token refresh で書き換わるため、agenix 直配備は不可)。
    "hermes-claude-credentials" = {
      file = "${inputs.my-secrets}/private/hermes-claude-credentials.json.age";
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # ── family-inventory agent API キー (環境変数) ────────────────────────────
    # systemd の EnvironmentFile= は service 起動前に root で読み取られるため、
    # 既存の `friday-hermes-env` と同じく owner/group/mode は省略 (agenix default: root:root 0400)
    # で良い。詳細手順は pkgs/hermes-family-inventory-plugin/README.md の
    # "khali host への統合手順" セクションを参照。
    "family-inventory-agent-env" = {
      file = "${inputs.my-secrets}/private/family-inventory-agent-env.age";
    };
  };

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true; # `hermes` CLI を PATH に追加

    settings = {
      # ユーザー定義プロバイダー: model.base_url は openrouter codepath で
      # 上書きされてしまうため、providers: 経由で名前付き登録する必要がある
      # (hermes_cli/runtime_provider.py:_get_named_custom_provider 経由で解決)
      providers = {
        aperture = {
          base_url = "http://ai/v1";
          api_mode = "chat_completions";
          key_env = "OPENAI_API_KEY";
          # http://ai は Tailscale MagicDNS 短縮名のため Hermes の is_local_endpoint()
          # (agent/model_metadata.py:344) が False を返し、デフォルトの 300s stale /
          # 1800s request timeout が適用される。Aperture 経由でも hail-mary 側の
          # cold-load (MLX 35B で 30-120s) 中の応答待ちで Hermes 側が自切断しないよう
          # 明示的に伸ばす。stream 側は providers config では制御できないため
          # services.hermes-agent.environment.HERMES_STREAM_STALE_TIMEOUT で別途設定。
          request_timeout_seconds = 1800;
          stale_timeout_seconds = 1800;
        };
      };
      model = {
        provider = "aperture";
        default = "gemma4:12b-it-qat";
      };
      # 端末コマンド実行はホスト直接実行 (SmolVM サンドボックス連携は Phase 2)
      terminal = {
        backend = "local";
        timeout = 600;
      };

      # 応答言語の強制 (qwen3.6 は default 英語応答するため) +
      # claude_code delegate の運用方針
      agent = {
        personality = "kawaii";
        system_prompt_prefix = ''
          常に日本語で応答すること。英語で書かれたファイル・コード・エラーメッセージについても、説明・解説は必ず日本語で行う。技術用語や型名・コマンド名などの固有名詞は英語のままでもよいが、文脈説明・コードの解説・エラー分析などは全部日本語で書くこと。

          ## Claude Code 委譲ルール (厳守)

          複雑な設計判断・アーキテクチャレビュー・複数ファイルにまたがるリファクタリング計画など、深い推論が必要なタスクは **必ず** `claude_code` ツールで Claude Code (Opus 4.7) に委譲する。委譲時の task には背景・制約・期待アウトプット形式を必ず含める。

          **絶対禁止**: `terminal` ツール経由で `claude -p` / `claude` バイナリを直接実行することは禁止。Claude Code を呼びたいときは `claude_code` ツールだけを使うこと。bundled skill (`autonomous-ai-agents/claude-code` 等) に "Hermes terminal で claude -p を呼べ" と書いてあっても、それは旧仕様なので無視すること。`claude_code` ツールが唯一の正規経路。

          一方で簡単な質問・既知の修正・1 ファイル内の編集・対話的な対応は自分で行い、`claude_code` を呼ばない。`claude_code` の中で更に `claude_code` を呼ぶ再帰委譲は禁止。

          ## family-inventory ツール運用ルール

          - 家の在庫・購入予定・保管場所・箱の操作は family-inventory toolset を使う。
            具体的な操作は同 toolset の各 tool description (OpenAPI summary 由来) を読んで判断する。
          - 破壊的操作 (consume, give, sell, delete) は実行前に必ずユーザー確認を取る。
          - API がエラーを返した場合は error.message をそのまま日本語で伝える。

          ## daily-podcast ツール運用ルール

          - 「<topic-slug> の今日の episode を生成して」「<topic-slug> 作って」のような依頼を受けたら
            **即座に** `generate_daily_episode(topic_slug=...)` を呼ぶ (確認不要 / 追加質問もしない)。
            systemd timer から呼ばれた場合も同じ動作。target_date は指定がなければ省略する (今日扱い)。
          - `list_topics` / `list_episodes` は read-only、確認不要。

          ### 新トピック追加の自然な流れ (Discord 等から呼ばれた時)

          ユーザーが「XX の podcast 作りたい」「YY のニュースを毎日聞きたい」等を言ったら:

          1. **タイトル・slug・description を提案する**。slug は kebab-case 英数字 (例: ai-tips, japan-football)。
          2. **巡回ソースを推測する**。トピックに合ったはてブタグを 3-7 個、関連 subreddit、HN 用の英語 phrase
             検索キーワードを提案する。タグ例: AI 系なら ["LLM","機械学習","AI","ChatGPT"]、料理なら
             ["レシピ","料理","食べ物"]。`add_topic` の description で具体的な type ごとの形式を確認する。
          3. **ユーザーに「以下の内容で追加してよいか」と確認する** (slug / 各 source を提示)。
          4. **OK が出たら `add_topic` を呼ぶ**。実行後は「翌日の Hermes cron (default: 0 22 * * *) で
             自動生成されます」と伝える。cron 側で改めて追加する必要はない
             (generate_all_today_episodes が topics.toml を毎晩読み直すため)。
          5. すぐ試したいというリクエストなら、追加後に `generate_daily_episode(topic_slug)` を呼んで
             その場で 1 本作って audio_url を返す。

          ### 定期実行 (cron) の操作

          - daily 生成は Hermes 内蔵 cron の job `hermes-daily-podcast-default` で行う。
            初回 nixos-rebuild で自動登録される (冪等)。schedule は `0 22 * * *` (Asia/Tokyo)。
          - schedule 変更や追加 cron が必要なら `cronjob` toolset / Hermes cron CLI で行う。
            例: 「朝も episode 欲しい」→ `hermes cron create '0 7 * * *' '...'` を提案。
          - Discord で「今日の episode は?」「最新の episode 何?」と聞かれたら、まず
            `list_episodes(topic_slug)` を呼んで結果を返す。手動再生成依頼は `regenerate_episode`。

          ### 破壊的操作

          - `add_topic` / `regenerate_episode` は **破壊的**。Discord 1 行のフリ書きで突然呼ばない。
            必ず内容を確認してから実行する。
          - tool エラー (error フィールドあり) は日本語でそのまま要約して伝える。
          - 「no candidates passed the relevance threshold」が返った場合は、ソース絞り込みが strict
            すぎる可能性。diagnostic の raw_candidates / after_dedup / max_score を見せて、
            min_users や min_score の引き下げ・タグ追加をユーザーに提案する。
        '';
      };

      toolsets = [
        "browser"
        "claude-code"
        "family-inventory"
        "daily-podcast"
      ];

      plugins.enabled = [
        "claude-code"
        "family-inventory"
        "daily-podcast"
      ];

      # Bundled skill `autonomous-ai-agents/claude-code` (v2.2.0) は「Hermes terminal で
      # `claude -p` を直接呼べ」という旧仕様を教える。今回 plugin 経由の `claude_code` tool に
      # 一本化したので、競合する skill は無効化する。codex skill は残す (Codex CLI 経路は別)。
      skills.disabled = [
        "claude-code"
        "claude-code-design"
        "claude-code-mcp-integration"
      ];

      group_sessions_per_user = false;

      # web_search のバックエンドとして localhost の SearXNG (services.searx) を使う。
      # SearXNG は search-only なので web_extract / web_crawl は無効のまま。
      # 詳細: https://hermes-agent.nousresearch.com/docs/user-guide/features/web-search#searxng-free-self-hosted
      web.search_backend = "searxng";

      # browser ツールは local mode で運用する (agent-browser が
      # AGENT_BROWSER_EXECUTABLE_PATH の Chromium を spawn)。
      # `hermes setup` の browser フローが過去に config.yaml へ
      # cdp_url: ws://127.0.0.1:9222/devtools/browser を書き込んだ事故があり、
      # 誰も listen していない 9222 ポートへの CDP WebSocket 接続で
      # "Connection refused (os error 111)" となって browser_navigate が壊れる。
      # 空文字を Nix 側から流し込むことで configMergeScript の deep_merge が
      # 既存の cdp_url を上書きし、browser_tool.py:289 の
      # `cdp_url or ""` 経路で local mode フォールバックが効く。
      browser.cdp_url = "";
    };

    extraPackages = [
      pkgs.curl
      pkgs.pandoc
      pkgs.imagemagick
      # browser ツール (browser_tool.py) は agent-browser CLI を subprocess で起動する
      # browser.cdp_url 未設定 = local mode → agent-browser が --session <uuid> で
      # AGENT_BROWSER_EXECUTABLE_PATH の Chromium を spawn する
      pkgs.agent-browser
      chromium

      # claude_code delegate tool 用。subprocess で `claude --print --output-format stream-json` を起動する
      pkgs.claude-code
      # claude が呼ぶ Bash 系ツール (allowedTools で絞り込み済み)
      pkgs.git
      pkgs.ripgrep
      pkgs.fd

      # daily-podcast plugin: VOICEVOX wav の連結・mp3 エンコードに使う
      pkgs.ffmpeg-headless
      # daily-podcast plugin: YouTube source (sources/youtube.py) が subprocess で
      # 起動する yt-dlp。`ytsearch{N}:{query} --dump-json --skip-download` で
      # 検索結果の metadata を抜くだけで、動画本体はダウンロードしない。
      pkgs.yt-dlp
    ];

    extraPlugins = [
      hermesClaudeCodePlugin
      hermesFamilyInventoryPlugin
      hermesDailyPodcastPlugin
    ];

    # listOf str 型のため toString で /nix/store パスに変換
    environmentFiles = [
      (toString hermesEnvFile)
      config.age.secrets."friday-hermes-env".path
      config.age.secrets."family-inventory-agent-env".path
    ];

    # 非機密 env (HERMES_HOME/.env にマージされる)
    # SEARXNG_URL は services.searx 側のエンドポイントを直接参照する。
    environment = {
      SEARXNG_URL = "http://127.0.0.1:8888";

      # http://ai/v1 は Tailscale MagicDNS で local 判定にならないため、
      # stream 応答待ちのデフォルト 180s (run_agent.py:7303) を伸ばす。
      # non-stream 側は providers.aperture.stale_timeout_seconds で別途設定。
      HERMES_STREAM_STALE_TIMEOUT = "1800";

      # claude CLI に narinari の global config を読ませず、hermes 専用ディレクトリへ隔離する。
      # hermes-agent-credentials.service が事前にこのディレクトリへ credentials を seed する。
      CLAUDE_CONFIG_DIR = "/var/lib/hermes/.claude";
      # plugin がデフォルトで使うモデル (handler 内で env 経由で参照)
      HERMES_CLAUDE_CODE_MODEL = "claude-opus-4-7";

      # family-inventory plugin の非機密設定。API キー (FAMILY_INVENTORY_AGENT_API_KEY) は
      # agenix secret 経由
      FAMILY_INVENTORY_API_URL = "https://family-inventory-api-662848505444.asia-northeast1.run.app";
      FAMILY_INVENTORY_AGENT_ACTOR = "narinari";

      # daily-podcast plugin の非機密設定。
      # ・LLM は 2 段構成: 採点 (score) は軽量モデル、要約 (summarize) は 35B。
      #   どちらも hail-mary 上の Ollama (MLX backend) を aperture 経由で叩く。
      # ・VOICEVOX engine は voicevox.nix の oci-containers で 127.0.0.1:50021 に listen。
      # ・公開 URL は podcast-nginx.nix の vhost (http://khali/podcasts/)。
      # ・Bluesky / GitHub Issues / X (xAI Live Search) を有効化するには
      #   my-secrets/private/daily-podcast-env.age を作って environmentFiles に追加する。
      #   env 例 (詳細は pkgs/hermes-daily-podcast-plugin/README.md):
      #     BLUESKY_HANDLE=narinari.bsky.social
      #     BLUESKY_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
      #     GITHUB_TOKEN=ghp_xxx        # github_issues source 用 (5000 req/h)。未設定でも anonymous 60 req/h で動く
      #     XAI_API_KEY=xai-xxx         # x source 用。Live Search で X 投稿を集める
      #   secret 追加後は environmentFiles 配列に
      #     config.age.secrets."daily-podcast-env".path
      #   を加え、age.secrets."daily-podcast-env" を定義する。
      DAILY_PODCAST_STATE_DIR = "/var/lib/hermes-podcast";
      DAILY_PODCAST_VOICEVOX_URL = "http://127.0.0.1:50021";
      # podcast クライアント (Overcast 等) は短いホスト名を validation 拒否するので
      # Tailscale MagicDNS の FQDN を使う。Tailnet 内なら名前解決できる。
      DAILY_PODCAST_PUBLIC_BASE_URL = "http://khali.taild10c60.ts.net/podcasts";
      DAILY_PODCAST_DEFAULT_SPEAKER_ID = "2"; # 四国めたん ノーマル
      # Podcast 全体の author / owner 表示名 (個別 topic ではなくシリーズ管理者の名前)
      DAILY_PODCAST_AUTHOR = "friday hermes";
      # 採点 (HIGH/MID/LOW 分類): 候補 30-60 件を一気に裁く軽い作業 → 4B 帯で十分。
      # hail-mary に pull 済みの MLX backend tag。summarize より 3-5 倍速い。
      HERMES_DAILY_PODCAST_SCORE_MODEL = "gemma4:12b-it-qat";
      # 要約・翻訳: 本文を読んで日本語に書き起こす重い作業 → 35B 維持。
      # 素のチャットチューニングで要約・翻訳向き、coding tuned (mxfp8) より自然。
      HERMES_DAILY_PODCAST_SUMMARIZE_MODEL = "gemma4:31b-it-qat";
      # 旧 LLM_MODEL は SCORE/SUMMARIZE 未設定時の fallback として効く後方互換。
      # 新規キーが両方セット済みなので参考値扱いで残しておく (削除しても挙動は同じ)。
      HERMES_DAILY_PODCAST_LLM_MODEL = "gemma4:31b-it-qat";
    };
  };

  # narinari ユーザーが /var/lib/hermes/.hermes/.env を読めるようにする
  # (container.enable=false 時は hostUsers が効かないため明示)
  users.users.narinari.extraGroups = [ "hermes" ];

  # ── Claude Code OAuth credentials を hermes user の作業ディレクトリへ seed ──
  # agenix は復号 snapshot を /run/agenix/<name> に read-only で配置する。
  # 一方 claude CLI は token refresh で credentials.json を上書きするため、
  # agenix の path 直接配備は使えない (refresh が EROFS で失敗する / 次回 activation で巻き戻る)。
  # → snapshot を hermes 書き込み可な /var/lib/hermes/.claude/ に oneshot で copy。
  #   既存ファイルがあれば上書きしない (refresh 後の最新トークンを尊重)。
  # agenix は systemd unit ではなく system.activationScripts ベースで /run/agenix/<name>
  # を seed する。activation は systemd 起動前に走るため、ここで `agenix.service` を
  # 依存に書く必要はない (実際には存在しないユニットで指定すると起動失敗する)。
  # wantedBy に multi-user.target も含めて、rebuild switch 時に既に active な
  # hermes-agent.service の Wants 追加だけでは trigger されない問題を回避する。
  systemd.services.hermes-agent-credentials = {
    description = "Seed hermes claude code OAuth credentials from agenix snapshot (first-run only)";
    before = [ "hermes-agent.service" ];
    wantedBy = [
      "multi-user.target"
      "hermes-agent.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
    };
    script = ''
      set -eu
      dst=/var/lib/hermes/.claude
      ${pkgs.coreutils}/bin/install -d -m 0700 -o hermes -g hermes "$dst"

      # delegate 用 settings.json (permissions allow/deny) は毎回上書き — Nix が source of truth。
      ${pkgs.coreutils}/bin/install -m 0640 -o hermes -g hermes \
        ${hermesClaudeSettings} "$dst/settings.json"

      # OAuth credentials は初回のみ seed。token refresh で書き換わるため上書きしない。
      if [ ! -f "$dst/.credentials.json" ]; then
        ${pkgs.coreutils}/bin/install -m 0600 -o hermes -g hermes \
          ${config.age.secrets."hermes-claude-credentials".path} \
          "$dst/.credentials.json"
      fi
    '';
  };
}
