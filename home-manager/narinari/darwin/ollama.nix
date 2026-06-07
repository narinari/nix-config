_: {
  # Homebrew版を使用（MLXサポートのため）
  # services.ollama = {
  #   enable = true;
  #   environmentVariables = {
  #     OLLAMA_HOST = "0.0.0.0:11434";
  #   };
  # };

  # CLI / SSH shell 経由の env (`ollama` CLI 直叩き用)。
  # GUI app (Homebrew ollama-app cask) は launchd 起動なので別途 launchctl setenv が必要。
  home.sessionVariables = {
    OLLAMA_HOST = "0.0.0.0:11434";
    OLLAMA_KEEP_ALIVE = "24h";
    OLLAMA_NUM_PARALLEL = "2";
    OLLAMA_MAX_LOADED_MODELS = "3";
  };

  # Homebrew ollama-app は GUI app として launchd 経由で起動するため shell の
  # env を引き継がない。ログイン直後に launchctl setenv を実行する LaunchAgent
  # を作り、ollama-app 起動前に user-scope env を反映させる。
  # 目的:
  #   - OLLAMA_KEEP_ALIVE=24h で MLX モデルのアンロードを抑止し、khali Hermes →
  #     aperture → hail-mary Ollama の経路で cold-load 起因の Aperture 502 を排除する。
  #   - OLLAMA_NUM_PARALLEL / MAX_LOADED_MODELS で複数モデル同時保持と並列推論を許可。
  launchd.agents.ollama-env = {
    enable = true;
    config = {
      Label = "com.narinari.ollama-env";
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          launchctl setenv OLLAMA_HOST 0.0.0.0:11434
          launchctl setenv OLLAMA_KEEP_ALIVE 24h
          launchctl setenv OLLAMA_NUM_PARALLEL 2
          launchctl setenv OLLAMA_MAX_LOADED_MODELS 3
        ''
      ];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };
}
