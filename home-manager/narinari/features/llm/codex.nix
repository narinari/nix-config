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

  # profile ファイルの中身。base config (config.toml) の上にレイヤーされるので、
  # 差分になるキーだけ書けばよいが、base のデフォルトが変わっても profile の意味が
  # ブレないよう model / provider / context window は明示しておく。
  mkProfile = model: ''
    # codex --profile <name> で config.toml の上にレイヤーされる。
    model = "${model}"
    model_provider = "tailscale-aperture"
    model_context_window = 262144
  '';

  # $CODEX_HOME 直下に配置するファイル群。key がそのままファイル名になる。
  codexFiles = {
    "config.toml" = ''
      # Codex CLI 設定 (Tailscale Aperture 経由)
      #
      # デフォルトは coding 用 qwen3.8 (hail-mary on MLX, Aperture 経由)。
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

      # NOTE: ここに [profiles.<name>] テーブルを書いてはいけない。codex-cli 0.146 で
      # profile は「$CODEX_HOME/<name>.config.toml を base config にレイヤーする」方式
      # (CONFIG_PROFILE_V2) に変わり、config.toml に legacy な [profiles.*] が残っていると
      # `--profile <name>` がエラーになる。しかも exit code 0 を返すため silent failure に
      # なる。profile は下の codexFiles に <name>.config.toml として足すこと。
    '';

    # 実装委譲用のメイン profile (Claude codex-implement skill から呼ばれる主用途)
    "local_qwen3_8_coding.config.toml" = mkProfile "qwen3.8:27b-mxfp8";

    # フォールバック: 汎用対話 / 指示追従重視のとき
    "local_gemma4.config.toml" = mkProfile "gemma4:26b-a4b-it-q8_0";
  };

  codexFilePkgs = lib.mapAttrs (name: text: pkgs.writeText "codex-${name}" text) codexFiles;
in
{
  # Linux: nix パッケージからインストール (macOS: Homebrew cask で管理)
  home.packages = lib.optionals isLinux [
    inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    ''
      run mkdir -p "$HOME/.codex"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: file: ''
        dst="$HOME/.codex/${name}"
        if [ -f "$dst" ] && ! ${pkgs.diffutils}/bin/diff -q "$dst" "${file}" > /dev/null 2>&1; then
          echo "codex: ${name} has changed:"
          ${pkgs.diffutils}/bin/diff -u "$dst" "${file}" || true
        fi
        run cp -f "${file}" "$dst"
        run chmod 644 "$dst"
      '') codexFilePkgs
    )
  );
}
