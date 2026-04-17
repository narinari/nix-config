# Codex CLI (OpenAI) の設定管理
#
# ~/.codex/config.toml をデプロイする。
# Tailscale Aperture 経由でローカル LLM (Ollama) やクラウドモデルにアクセスする構成。
#
# Aperture プロバイダーを経由することで:
# - APIキー管理を Aperture に集約（クライアント側にキー不要）
# - Tailscale identity によるゼロキー認証
# - http://ai/v1 の統一エンドポイント
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  inherit (pkgs.stdenv) isLinux;

  codexConfigFile = pkgs.writeText "codex-config.toml" ''
    # Codex CLI 設定 (Tailscale Aperture 経由)
    model = "o3-mini"
    model_provider = "tailscale-aperture"

    # Tailscale Aperture AIゲートウェイ
    [model_providers.tailscale-aperture]
    name = "Tailscale Aperture"
    base_url = "http://ai/v1"

    # ローカル Ollama (Aperture 未経由で直接接続する場合)
    [model_providers.local-ollama]
    name = "Local Ollama"
    base_url = "http://localhost:11434/v1"
    env_key = "OLLAMA_API_KEY"
    env_key_instructions = "Ollama does not require an API key"

    # ローカルモデルプロファイル (Aperture 経由)
    [profiles.local]
    model = "qwen3.5:35b-a3b"
    model_provider = "tailscale-aperture"
    model_context_window = 131072
  '';
in
{
  # Linux: nix パッケージからインストール (macOS: Homebrew cask で管理)
  home.packages = lib.optionals isLinux [
    inputs.codex-cli-nix.packages.${pkgs.system}.default
  ];

  home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    config="$HOME/.codex/config.toml"
    run mkdir -p "$HOME/.codex"
    if [ -f "$config" ]; then
      if ! ${pkgs.diffutils}/bin/diff -q "$config" "${codexConfigFile}" > /dev/null 2>&1; then
        echo "codex: config.toml has changed:"
        ${pkgs.diffutils}/bin/diff -u "$config" "${codexConfigFile}" || true
      fi
    fi
    run cp -f "${codexConfigFile}" "$config"
    run chmod 644 "$config"
  '';
}
