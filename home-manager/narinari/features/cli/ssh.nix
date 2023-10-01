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
          extraOptions = { TCPKeepAlive = "yes"; };
        };

        "github.com" = {
          user = "git";
          extraOptions = { TCPKeepAlive = "yes"; };
        };
      };
    };
  };
}
