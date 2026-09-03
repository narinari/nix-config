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
    #
    # デフォルトは coding 用 qwen3.6 (hail-mary on MLX, Aperture 経由)。
    # 他用途は profile を明示すること: `codex --profile local_gemma4 ...`
    # Claude Code の codex-implement skill から呼ばれる主要経路でもある
    # (関連: docs/codex-implement-claude-bridge.md)
    model = "qwen3.8:27b-mxfp8"
    model_provider = "tailscale-aperture"
    model_context_window = 262144

    # Tailscale Aperture AIゲートウェイ
    [model_providers.tailscale-aperture]
    name = "Tailscale Aperture"
    base_url = "http://ai/v1"
    wire_api = "responses"

    # ローカル Ollama (Aperture 未経由で直接接続する場合)
    [model_providers.local-ollama]
    name = "Local Ollama"
    base_url = "http://localhost:11434/v1"
    env_key = "OLLAMA_API_KEY"
    env_key_instructions = "Ollama does not require an API key"

    # 実装委譲用デフォルト profile (Claude codex-implement skill から呼ばれる主用途)
    # NOTE: TOML の bare key にドット (`.`) を含めると dotted-key として table 階層に
    # 展開されてしまう (例: `[profiles.local_qwen3.6_coding]` は
    # `profiles -> local_qwen3 -> 6_coding` の 4 段 table になる) ため、
    # profile 名は必ずアンダースコア区切りで書く。
    [profiles.local_qwen3_8_coding]
    model = "qwen3.8:27b-mxfp8"
    model_provider = "tailscale-aperture"
    model_context_window = 262144

    # フォールバック: 汎用対話 / 指示追従重視のとき
    [profiles.local_gemma4]
    model = "gemma4:26b-a4b-it-q8_0"
    model_provider = "tailscale-aperture"
    model_context_window = 262144
  '';
in
{
  # Linux: nix パッケージからインストール (macOS: Homebrew cask で管理)
  home.packages = lib.optionals isLinux [
    inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
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
