{ pkgs, lib, ... }:

let
  inherit (pkgs) stdenv;
  inherit (lib) optionalAttrs;
in {
  imports = [
    ./btop.nix
    ./direnv.nix
    ./docker.nix
    ./git.nix
    ./go.nix
    ./gnupg.nix
    ./haskell.nix
    ./kubernetes.nix
    ./nodejs.nix
    ./lf.nix
    ./less.nix
    ./rust.nix
    ./ssh.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.sessionVariables = { COLORTERM = "truecolor"; };

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
    (btop.overrideDerivation
      (oldAttrs: { stdenv = gcc12Stdenv; })) # 2023/1/17 時点でビルドできないのでパッチ
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
    wezterm
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

    nodejs_20

    # backup
    restic
    kopia

    natscli
    just

    ditaa
  ];

  programs = {
    aria2.enable = true;
    atuin = {
      enable = true;
      settings.auto_sync = true;
    };
    bat.enable = true;
    eza = {
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
      } // optionalAttrs stdenv.isDarwin {
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
  };
}
