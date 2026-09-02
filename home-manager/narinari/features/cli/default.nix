{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./claude-podman.nix
    ./docker.nix
    ./go.nix
    ./haskell.nix
    ./kubernetes.nix
    ./nodejs.nix
    ./rust.nix
  ];

  home.packages = with pkgs; [
    nix-prefetch
    nix-prefetch-scripts
    nix-prefetch-github
    nixpkgs-review
    nix-update
    nixpkgs-fmt
    nixos-shell
    manix
    nil # Nix LSP
    nixfmt # Nix formatter (RFC style; `nixfmt-rfc-style` is now an alias for this)

    # espeak
    socat
    websocat

    # media
    ffmpeg
    (streamlink.overridePythonAttrs (_: {
      doCheck = false;
    }))
    yt-dlp
    # beets-unstable

    bc # Calculator
    kalker # calc
    eva # calc
    bottom # System viewer
    ncdu # disk space info (a better du)
    diffsitter # Better diff
    fastfetch
    hexyl
    zenith
    # dust
    procs
    hyperfine
    pwgen
    sd # find & replace
    bandwhich
    btop
    pueue
    file
    viddy # alt watch
    asciinema # record the terminal
    prettyping # a nicer ping

    pv
    rclone

    unar
    # dbeaver
    # mycli # broken: sqlglot version mismatch (requires 27.*, nixpkgs has 28.x)
    # obsidian
    # logseq
    # anytype
    # cloudflared
    # tmate
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
    # wireshark
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

    ditaa
  ];

  programs = {
    aria2.enable = true;
    atuin = {
      enable = true;
      settings = {
        auto_sync = true;
        style = "compact";
        invert = true;
        inline_height = 20;
      };
    };
    bat.enable = true;
    eza = {
      enable = true;
      enableZshIntegration = true;
    };
    jq.enable = true;
    fzf = {
      enable = true;
      tmux.enableShellIntegration = true;
      tmux.shellIntegrationOptions = [ "-p 80%" ];
      defaultCommand = ''rg --files --hidden --glob "!.git"'';
      defaultOptions = [
        "--height 40%"
        "--border"
        "--reverse"
        "--inline-info"
      ];
      changeDirWidget = {
        command = "fd --type d"; # alt+c
        options = [ "--preview 'tree -C {} | head -200'" ];
      };
      fileWidget = {
        command = "fd --type f";
        options = [ "--preview 'head {}'" ];
      };
      # atuin が Ctrl-R を使うため、fzf の Ctrl-R バインドを無効化する。
      historyWidget = {
        command = "";
      };
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

    tealdeer.enable = true;
    zoxide.enable = true;
    nushell.enable = false;
    # zellij.enable = true;
  };
}
