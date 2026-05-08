# Hermes Agent (Nous Research) — Tailscale Aperture 経由で hail-mary Ollama を利用
#
# 設計:
#   - 推論バックエンドは hail-mary 上の Ollama (qwen3.6:35b-a3b-coding-mxfp8)
#   - 直接接続ではなく Tailscale Aperture (http://ai/v1) を経由
#     → 認証は Aperture が Tailscale identity で代行 (実 API キー不要)
#   - 既存 Codex CLI 構成 (home-manager/narinari/features/llm/codex.nix) と同経路
#
# テスト:
#   systemctl status hermes-agent
#   journalctl -u hermes-agent -f
#   hermes version
{
  pkgs,
  inputs,
  config,
  ...
}:

let
  # Aperture は Tailscale identity で認証するため実 API キーは不要だが、
  # hermes-agent モジュールが environmentFiles を要求するためダミーを供給する。
  hermesEnvFile = pkgs.writeText "hermes-env" ''
    OPENAI_API_KEY=aperture-tailscale-identity
    GATEWAY_ALLOW_ALL_USERS=true

    DISCORD_ALLOWED_ROLES=1028883038228189185
    DISCORD_HOME_CHANNEL=1500767462637961246
  '';
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  age.secrets."friday-hermes-env" = {
    file = "${inputs.my-secrets}/private/friday-hermes-env.age";
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

      # 応答言語の強制 (qwen3.6 は default 英語応答するため)
      agent = {
        personality = "kawaii";
        system_prompt_prefix = "常に日本語で応答すること。英語で書かれたファイル・コード・エラーメッセージについても、説明・解説は必ず日本語で行う。技術用語や型名・コマンド名などの固有名詞は英語のままでもよいが、文脈説明・コードの解説・エラー分析などは全部日本語で書くこと。";
      };

      group_sessions_per_user = false;
    };

    extraPackages = [
      pkgs.curl
      pkgs.pandoc
      pkgs.imagemagick
    ];

    # listOf str 型のため toString で /nix/store パスに変換
    environmentFiles = [
      (toString hermesEnvFile)
      config.age.secrets."friday-hermes-env".path
    ];
  };

  # narinari ユーザーが /var/lib/hermes/.hermes/.env を読めるようにする
  # (container.enable=false 時は hostUsers が効かないため明示)
  users.users.narinari.extraGroups = [ "hermes" ];
}
