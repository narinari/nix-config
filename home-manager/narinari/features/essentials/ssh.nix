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

      # 26.05 以降 matchBlocks は deprecated → settings へ移行 (OpenSSH directive 名)。
      settings = {
        "*" = {
          SendEnv = [ "COLORTERM" ];
          ControlMaster = "auto";
          ControlPersist = "10m";
          HashKnownHosts = false;
          UserKnownHostsFile = "/dev/null";
          ServerAliveInterval = 300;
          StrictHostKeyChecking = "no";
        };
        "github.com.private" = {
          HostName = "github.com";
          User = "git";
          Port = 22;
          ServerAliveInterval = 60;
          TCPKeepAlive = "yes";
        };
        "github.com" = {
          User = "git";
          ServerAliveInterval = 60;
          TCPKeepAlive = "yes";
        };
      };
    };
  };
}
