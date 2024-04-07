{ pkgs, lib, config, inputs, outputs, ... }:

{
  programs = {
    ssh = {
      enable = true;
      controlMaster = "auto";
      controlPersist = "10m";
      hashKnownHosts = false;
      userKnownHostsFile = "/dev/null";
      serverAliveInterval = 300;

      extraOptionOverrides = {
        VerifyHostKeyDNS = "ask";
        VisualHostKey = "no";
        StrictHostKeyChecking = "no";
      } // lib.optionalAttrs pkgs.stdenv.isDarwin {
        # for macos
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
        HostkeyAlgorithms = "+ssh-rsa";
        PubkeyAcceptedAlgorithms = "+ssh-rsa";
      };

      matchBlocks = {
        "*" = { sendEnv = [ "COLORTERM" ]; };

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
