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

  age.secrets."friday-hermes-env" = {
    file = "${inputs.my-secrets}/private/friday-hermes-env.age";
  };

  # Claude Code OAuth credentials (Pro/Max sub) の暗号化スナップショット。
  # /run/agenix/hermes-claude-credentials に root:root 0400 で配置される。
  # hermes-agent-credentials.service が初回のみ /var/lib/hermes/.claude/.credentials.json
  # に hermes 所有でコピーする (token refresh で書き換わるため、agenix 直配備は不可)。
  age.secrets."hermes-claude-credentials" = {
    file = "${inputs.my-secrets}/private/hermes-claude-credentials.json.age";
    mode = "0400";
    owner = "root";
    group = "root";
  };

  # ── family-inventory agent API キー (環境変数) ────────────────────────────
  # TODO: my-secrets リポジトリ側で agenix により
  #   `private/family-inventory-agent-env.age`
  # を作成したら、以下 2 ブロックのコメントアウトを解除して
  # `sudo nixos-rebuild switch --flake .#khali` する。
  #
  # secret の中身 (1 行):
  #   FAMILY_INVENTORY_AGENT_API_KEY=<openssl rand -hex 32 で生成した値>
  #
  # systemd の EnvironmentFile= は service 起動前に root で読み取られるため、
  # 既存の `friday-hermes-env` と同じく owner/group/mode は省略 (agenix default: root:root 0400)
  # で良い。詳細手順は pkgs/hermes-family-inventory-plugin/README.md の
  # "khali host への統合手順" セクションを参照。
  #
  # age.secrets."family-inventory-agent-env" = {
  #   file = "${inputs.my-secrets}/private/family-inventory-agent-env.age";
  # };

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
        };
      };
      model = {
        provider = "aperture";
        default = "qwen3.6:35b-a3b-coding-mxfp8";
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
        '';
      };

      toolsets = [
        "browser"
        "claude-code"
        "family-inventory"
      ];

      plugins.enabled = [
        "claude-code"
        "family-inventory"
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
    ];

    extraPlugins = [
      hermesClaudeCodePlugin
      hermesFamilyInventoryPlugin
    ];

    # listOf str 型のため toString で /nix/store パスに変換
    environmentFiles = [
      (toString hermesEnvFile)
      config.age.secrets."friday-hermes-env".path
      # TODO: my-secrets に family-inventory-agent-env.age を追加した後、
      # 上の `age.secrets."family-inventory-agent-env"` ブロックと併せて
      # 以下のコメントアウトを解除すること。
      # config.age.secrets."family-inventory-agent-env".path
    ];

    # 非機密 env (HERMES_HOME/.env にマージされる)
    # SEARXNG_URL は services.searx 側のエンドポイントを直接参照する。
    environment = {
      SEARXNG_URL = "http://127.0.0.1:8888";
      # claude CLI に narinari の global config を読ませず、hermes 専用ディレクトリへ隔離する。
      # hermes-agent-credentials.service が事前にこのディレクトリへ credentials を seed する。
      CLAUDE_CONFIG_DIR = "/var/lib/hermes/.claude";
      # plugin がデフォルトで使うモデル (handler 内で env 経由で参照)
      HERMES_CLAUDE_CODE_MODEL = "claude-opus-4-7";

      # family-inventory plugin の非機密設定。API キー (FAMILY_INVENTORY_AGENT_API_KEY) は
      # agenix secret 経由 (上記 environmentFiles の TODO を参照)。
      # TODO: Cloud Run デプロイ後の URL に置換すること (例: https://family-inventory-xxxxx-an.a.run.app)
      FAMILY_INVENTORY_API_URL = "https://CHANGE_ME_CLOUD_RUN_URL";
      FAMILY_INVENTORY_AGENT_ACTOR = "narinari";
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
