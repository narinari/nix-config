{
  pkgs,
  lib,
  config,
  inputs,
  outputs,
  ...
}:

{
  # SSH agent forwarding fix for tmux
  # Creates a symlink at a fixed path so tmux sessions can find the current agent
  home.file.".ssh/rc" = {
    text = ''
      #!/bin/sh
      if [ -n "$SSH_AUTH_SOCK" ] && [ "$SSH_AUTH_SOCK" != "$HOME/.ssh/ssh_auth_sock" ]; then
        ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
      fi

      # Handle xauth if X11 forwarding is enabled
      if read proto cookie && [ -n "$DISPLAY" ]; then
        if [ $(echo $DISPLAY | cut -c1-10) = 'localhost:' ]; then
          echo add unix:$(echo $DISPLAY | cut -c11-) $proto $cookie
        else
          echo add $DISPLAY $proto $cookie
        fi | xauth -q -
      fi
    '';
    executable = true;
  };

  programs = {
    ssh = {
      enable = true;
      enableDefaultConfig = false;

      extraOptionOverrides = {
        VerifyHostKeyDNS = "ask";
        VisualHostKey = "no";
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        # for macos
        AddKeysToAgent = "yes";
        UseKeychain = "yes";
        HostkeyAlgorithms = "+ssh-rsa";
        PubkeyAcceptedAlgorithms = "+ssh-rsa";
      };

      matchBlocks = {
        "*" = {
          sendEnv = [ "COLORTERM" ];
          controlMaster = "auto";
          controlPersist = "10m";
          hashKnownHosts = false;
          userKnownHostsFile = "/dev/null";
          serverAliveInterval = 300;
          extraOptions = {
            StrictHostKeyChecking = "no";
          };
        };

        "github.com.private" = {
          hostname = "github.com";
          user = "git";
          port = 22;
          serverAliveInterval = 60;
          extraOptions = {
            TCPKeepAlive = "yes";
          };
        };

        "github.com" = {
          user = "git";
          serverAliveInterval = 60;
          extraOptions = {
            TCPKeepAlive = "yes";
          };
        };
      };
    };
  };
}
