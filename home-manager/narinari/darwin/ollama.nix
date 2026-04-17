_: {
  # Homebrew版を使用（MLXサポートのため）
  # services.ollama = {
  #   enable = true;
  #   environmentVariables = {
  #     OLLAMA_HOST = "0.0.0.0:11434";
  #   };
  # };

  home.sessionVariables = {
    OLLAMA_HOST = "0.0.0.0:11434";
  };
}
