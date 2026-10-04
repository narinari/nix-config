{ lib, ... }:
let
  # Homebrew ollama-app (MLX runner) 向けの user-scope env。
  # CLI / SSH shell (home.sessionVariables) と GUI app (launchctl setenv) の両方に
  # 同じ値を流すため 1 箇所で定義する。各値の根拠は docs/hail-mary-ollama.md。
  #
  #   OLLAMA_HOST              Tailscale / aperture から到達できるよう全 IF で listen
  #   OLLAMA_KEEP_ALIVE        khali Hermes の約 1 時間周期ジョブが毎回 cold-load
  #                            (27B で ~10s + cold prefill) を払わないよう 24h 常駐。
  #                            aperture 経由の cold-load 起因 502 の排除も兼ねる
  #   OLLAMA_MAX_LOADED_MODELS 既定モデル (qwen3.8:27b-mlx 18GB) + fallback
  #                            (gemma4:26b-a4b-it-q8_0 28GB) の 2 本まで。3 本同居は
  #                            64GB (GPU 可視 48GiB) で Metal OOM 実績あり
  #
  # 設定しないもの:
  #   OLLAMA_NUM_PARALLEL      MLX runner は無視して常に Parallel:1 (server.log で確認)
  #   OLLAMA_CONTEXT_LENGTH    既定 262144 のまま。MLX は KV を遅延確保するため実害なく、
  #                            codex 側 model_context_window=262144 との不整合で
  #                            silent truncation を招くリスクの方が大きい
  #   OLLAMA_FLASH_ATTENTION / OLLAMA_KV_CACHE_TYPE  llama.cpp runner 向け。MLX 無関係
  ollamaEnv = {
    OLLAMA_HOST = "0.0.0.0:11434";
    OLLAMA_KEEP_ALIVE = "24h";
    OLLAMA_MAX_LOADED_MODELS = "2";
  };
  setenvScript = builtins.concatStringsSep "\n" (
    lib.mapAttrsToList (k: v: "launchctl setenv ${k} ${lib.escapeShellArg v}") ollamaEnv
  );
in
{
  # Homebrew版を使用（MLXサポートのため）
  # services.ollama = {
  #   enable = true;
  #   environmentVariables = {
  #     OLLAMA_HOST = "0.0.0.0:11434";
  #   };
  # };

  # CLI / SSH shell 経由の env (`ollama` CLI 直叩き用)。
  # GUI app (Homebrew ollama-app cask) は launchd 起動なので別途 launchctl setenv が必要。
  home.sessionVariables = ollamaEnv;

  # Homebrew ollama-app は GUI app として launchd 経由で起動するため shell の
  # env を引き継がない。ログイン直後に launchctl setenv を実行する LaunchAgent
  # を作り、ollama-app 起動前に user-scope env を反映させる。
  # 注意: launchctl setenv は揮発的 (再起動で消える) なので、この agent の
  # RunAtLoad が唯一の永続化手段。rebuild 後は Ollama.app の再起動も必要
  # (setenv は新規 spawn プロセスにしか効かない)。
  # setenv/getenv は呼び出し元の launchd ドメインに作用する。agent と GUI app は
  # gui/UID で一致するが、ssh セッションは user/UID なので ssh から getenv しても
  # 空に見える (偽陰性)。確認は `launchctl print gui/$(id -u) | grep OLLAMA_`。
  launchd.agents.ollama-env = {
    enable = true;
    config = {
      Label = "com.narinari.ollama-env";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        setenvScript
      ];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
