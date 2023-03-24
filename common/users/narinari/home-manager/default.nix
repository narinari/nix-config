{ pkgs, ... }:
let
  saml2aws_2_36_0 = pkgs.saml2aws.overrideAttrs (oldAttrs: rec {
    version = "2.36.0";
    src = pkgs.fetchFromGitHub {
      owner = "Versent";
      repo = "saml2aws";
      rev = "v2.63.0";
      sha256 = "sha256-Mux0n8uBnh9R+llA/XAVsfcDWIDxoaQkkSuhoSpIhl4=";
    };
  });
in {

  imports = [
    #   ./atuin.nix
    ./btop.nix
    #   ./git.nix
    #   ./emacs.nix
    #   ./ssh.nix
    ./tmux.nix
    #   ./xdg.nix
    ./zsh.nix
    ./kitty.nix
  ];

  home = {
    username = "narinari";
    packages = with pkgs; [
      # espeak
      socat
      websocat

      # media
      ffmpeg
      streamlink
      yt-dlp
      # beets-unstable

      # games
      # lutris
      # starsector

      # twitch
      # streamlink
      # chatterino2

      # comm
      # discord

      # dev
      bfg-repo-cleaner
      gitAndTools.git-absorb
      gitAndTools.gitui
      gitAndTools.git-machete
      gitAndTools.git-secrets
      git-filter-repo
      gitAndTools.gh
      colordiff
      delta
      tcpdump
      ghq
      gst

      # net
      croc
      # webwormhole
      wireshark
      dnsutils
      oneshot
      # tailscale
      xh

      # nix
      cachix
      comma
      nix-prefetch
      nix-prefetch-scripts
      nix-prefetch-github
      nixpkgs-review
      nix-update
      nixpkgs-fmt
      nixfmt
      nixos-shell
      manix
      rnix-lsp # nix lsp server

      # utils
      coreutils
      findutils
      gnugrep # macos ships with outdated version

      # cool cli tools
      kalker # calc
      neofetch
      ripgrep
      fd
      hexyl
      zenith
      # dust
      procs
      hyperfine
      pwgen
      rage
      sd # find & replace
      eva # calc
      bandwhich
      dogdns
      btop
      pueue
      file
      viddy # alt watch
      asciinema # record the terminal
      # ncdu # build error # disk space info (a better du)
      prettyping # a nicer ping
      sops
      starship
      zstd

      saml2aws # 2.36.2 buged
      # saml2aws_2_36_0

      # Android
      # android-studio
      # scrcpy

      # security?
      bitwarden-cli

      # backup
      restic
      kopia

      # rust
      cargo
      cargo-audit
      cargo-outdated
      # cargo-asm
      # cargo-bloat
      # cargo-crev
      cargo-expand
      cargo-flamegraph
      # cargo-fuzz
      # cargo-geiger
      cargo-sweep
      # cargo-tarpaulin # aarch64 not support
      cargo-udeps

      # haskell
      stack

      pv
      rclone

      feh # light-weight image viewer
      # ghidra-bin

      unar
      # dbeaver
      mycli
      # obsidian
      # logseq
      # anytype
      # cloudflared
      # tmate
      tmux
      # josm
      # ntp

      # Go
      go
      gopls

      # aws
      awscli2
      ssm-session-manager-plugin
      eksctl

      # kubernetes
      k9s
      kdash
      kubectl
      kubectx
      kubelogin-oidc
      # istioctl
      kubernetes-helm
      kind

      # docker
      docker-client
      docker-compose # docker manager
      docker-credential-helpers

      natscli
      just
    ];

    language.base = "ja_JP.UTF-8";

    sessionPath = [ "$HOME/.local/bin" ];

    file.".local/bin" = {
      source = ./home/bin;
      recursive = true;
      executable = true;
    };
  };

  programs = {
    aria2.enable = true;
    atuin = {
      enable = true;
      settings.auto_sync = true;
    };
    bat.enable = true;
    exa = {
      enable = true;
      enableAliases = true;
    };
    jq.enable = true;
    fzf = {
      enable = true;
      tmux.enableShellIntegration = true;
      tmux.shellIntegrationOptions = [ "-p 80%" ];
      defaultCommand = ''rg --files --hidden --glob "!.git"'';
      defaultOptions =
        [ "--height 40%" "--border" "--reverse" "--inline-info" ];
      changeDirWidgetCommand = "fd --type d"; # alt+c
      changeDirWidgetOptions = [ "--preview 'tree -C {} | head -200'" ];
      fileWidgetCommand = "fd --type f";
      fileWidgetOptions = [ "--preview 'head {}'" ];
      colors = {
        bg = "#1e1e1e";
        "bg+" = "#1e1e1e";
        fg = "#d4d4d4";
        "fg+" = "#d4d4d4";
      };
    };
    gpg.enable = true;
    navi.enable = true;
    sqls.enable = true;

    bashmount.enable = true;

    ssh = {
      enable = true;
      controlMaster = "auto";
      controlPersist = "10m";
      hashKnownHosts = false;
      userKnownHostsFile = "/dev/null";
      serverAliveInterval = 300;

      includes = [ "${./ssh/work/config}" ];

      extraOptionOverrides = {
        VerifyHostKeyDNS = "ask";
        VisualHostKey = "no";
        StrictHostKeyChecking = "no";
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

    tealdeer.enable = true;
    zoxide.enable = true;
    nushell.enable = false;
    zellij.enable = true;

    emacs = {
      enable = true;
      package = pkgs.emacsPgtk.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          # Fix OS window role (needed for window managers like yabai)
          (pkgs.fetchpatch {
            url =
              "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/fix-window-role.patch";
            sha256 = "+z/KfsBm1lvZTZNiMbxzXQGRTjkCFO4QPlEK35upjsE=";
          })
          # Use poll instead of select to get file descriptors
          (pkgs.fetchpatch {
            url =
              "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/poll.patch";
            sha256 = "jN9MlD8/ZrnLuP2/HUXXEVVd6A+aRZNYFdZF8ReJGfY=";
          })
          # Enable rounded window with no decoration
          (pkgs.fetchpatch {
            url =
              "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-29/round-undecorated-frame.patch";
            sha256 = "qPenMhtRGtL9a0BvGnPF4G1+2AJ1Qylgn/lUM8J2CVI=";
          })
          # Make Emacs aware of OS-level light/dark mode
          (pkgs.fetchpatch {
            url =
              "https://raw.githubusercontent.com/d12frosted/homebrew-emacs-plus/master/patches/emacs-28/system-appearance.patch";
            sha256 = "oM6fXdXCWVcBnNrzXmF0ZMdp8j0pzkLE66WteeCutv8=";
          })
        ];
      });
    };
  };

  # linux only
  # services = {
  #   syncthing.enable = true;
  #   easyeffects.enable = true;
  #   systembus-notify.enable = true;
  # };

  # systemd.user.startServices = "sd-switch";

}
