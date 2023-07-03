{ config, ... }:

{
  xdg.configFile."nixpkgs/config.nix".text = "{ allowUnfree = true; }";

  # Move Cache home to ~/Library/Caches, so it plays nicely with backups
  xdg.cacheHome = "${config.home.homeDirectory}/Library/Caches";

  home.sessionVariables = { SOPS_AGE_KEY_FILE = config.sops.age.keyFile; };

  launchd.agents.xdg_cache_home = {
    enable = true;
    config = {
      Program = "/bin/launchctl";
      ProgramArguments =
        [ "/bin/launchctl" "setenv" "XDG_CACHE_HOME" config.xdg.cacheHome ];
      RunAtLoad = true;
      StandardErrorPath = "/dev/null";
      StandardOutPath = "/dev/null";
    };
  };
}
