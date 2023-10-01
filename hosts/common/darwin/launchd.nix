{ config, ... }:

{
  launchd.user.envVariables.PATH = config.environment.systemPath;
}
