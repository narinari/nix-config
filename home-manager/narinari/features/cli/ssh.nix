{ pkgs, config, inputs, outputs, ... }:

{
  programs = {
    ssh = {
      enable = true;

      matchBlocks = {
        "github.com.private" = {
          hostname = "github.com";
          user = "git";
          port = 22;
          serverAliveInterval = 60;
          extraOptions = { TCPKeepAlive = "yes"; };
        };

        "github.com" = {
          user = "git";
          serverAliveInterval = 60;
          extraOptions = { TCPKeepAlive = "yes"; };
        };
      };
    };
  };
}
