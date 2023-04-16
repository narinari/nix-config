{ pkgs, ... }:

{
  imports = [ ./zsh.nix ];
  programs = {
    ssh = {
      enable = true;
      includes = [ "${./ssh/work/config}" ];
      matchBlocks = {
        "github.com.private" = {
          hostname = "github.com";
          user = "git";
          port = 22;
          identityFile = "~/.ssh/narinari.t/id_ed25519";
          identitiesOnly = true;

          extraOptions = { TCPKeepAlive = "yes"; };
        };

        "github.com" = {
          user = "git";
          identitiesOnly = true;

          extraOptions = { TCPKeepAlive = "yes"; };
        };
      };
    };
  };
}
