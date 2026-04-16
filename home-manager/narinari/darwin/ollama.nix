_: {
  services.ollama = {
    enable = true;
    environmentVariables = {
      OLLAMA_HOST = "0.0.0.0:11434";
    };
  };
}
