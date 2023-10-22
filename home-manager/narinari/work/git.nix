{ pkgs, config, ... }:

{
  xdg.configFile."git/config-c-fo".source = ./git/config-c-fo;

  programs.git = {
    extraConfig = {
      url = {
        "ssh://git@github.com/C-FO/".insteadOf = "https://github.com/C-FO/";
      };
    };
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
