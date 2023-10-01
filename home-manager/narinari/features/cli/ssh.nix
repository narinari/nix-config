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
