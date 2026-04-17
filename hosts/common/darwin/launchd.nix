{ config, ... }:

{
  # launchd.user.envVariables.PATH = config.environment.systemPath;
  launchd.user.envVariables = {
    OLLAMA_HOST = "0.0.0.0:11434";
  };
}
