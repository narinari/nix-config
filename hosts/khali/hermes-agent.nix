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
  ...
}:

let
  # Aperture は Tailscale identity で認証するため実 API キーは不要だが、
  # hermes-agent モジュールが environmentFiles を要求するためダミーを供給する。
  hermesEnvFile = pkgs.writeText "hermes-env" ''
    OPENAI_API_KEY=aperture-tailscale-identity
  '';
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

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
        timeout = 180;
      };
    };

    # listOf str 型のため toString で /nix/store パスに変換
    environmentFiles = [ (toString hermesEnvFile) ];
  };

  # narinari ユーザーが /var/lib/hermes/.hermes/.env を読めるようにする
  # (container.enable=false 時は hostUsers が効かないため明示)
  users.users.narinari.extraGroups = [ "hermes" ];
}
