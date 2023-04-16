{ pkgs, ... }:

{
  imports = [
    ./btop.nix
    ./tmux.nix
    ./docker.nix
    ./git.nix
    ./go.nix
    ./haskell.nix
    ./kubernetes.nix
    ./rust.nix
    ./zsh.nix
  ];

  home.packages = with pkgs; [
    # nix
    cachix
    comma # Install and run programs by sticking a , before them
    nix-prefetch
    nix-prefetch-scripts
    nix-prefetch-github
    nixpkgs-review
    nix-update
    nixpkgs-fmt
    nixos-shell
    manix
    # rnix-lsp # nix lsp server
    nil # Nix LSP
    nixfmt # Nix formatter

    # espeak
    socat
    websocat

    # media
    ffmpeg
    streamlink
    yt-dlp
    # beets-unstable

    bc # Calculator
    kalker # calc
    eva # calc
    bottom # System viewer
    # ncdu # build error # disk space info (a better du)
    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    diffsitter # Better diff
    neofetch
    hexyl
    zenith
    # dust
    procs
    hyperfine
    pwgen
    rage
    sd # find & replace
    bandwhich
    dogdns
    btop
    pueue
    file
    viddy # alt watch
    asciinema # record the terminal
    prettyping # a nicer ping
    sops
    starship
    zstd

    pv
    rclone

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
    #
    ltex-ls # Spell checking LSP

    # aws
    awscli2
    ssm-session-manager-plugin
    eksctl
    saml2aws

    # net
    croc
    # webwormhole
    wireshark
    dnsutils
    oneshot
    # tailscale
    xh

    # security?
    bitwarden-cli

    # utils
    coreutils
    findutils
    gnugrep # macos ships with outdated version

    # backup
    restic
    kopia

    natscli
    just
  ];

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

      matchBlocks = { "*" = { sendEnv = [ "COLORTERM" ]; }; };
    };

    tealdeer.enable = true;
    zoxide.enable = true;
    nushell.enable = false;
    zellij.enable = true;

    emacs = {
      enable = true;
      package = pkgs.emacsUnstablePgtk.overrideAttrs (old: {
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
}
