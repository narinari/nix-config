{ pkgs, config, ... }:

{
  xdg.configFile."git/config-c-fo".source = ./git/config-c-fo;

  programs.git = {
    includes = [
      {
        path = config.xdg.configFile."git/config-c-fo".source;
        condition = "gitdir:~/dev/src/github.com/C-FO/**";
      }
      {
        path = config.xdg.configFile."git/config-c-fo".source;
        condition = "gitdir:~/dev/src/github.com/narinari-freee/**";
      }
    ];
  };
}
