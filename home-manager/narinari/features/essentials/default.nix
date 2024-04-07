{ config, lib, pkgs, ... }:

{
  imports = [
    ./btop.nix
    ./direnv.nix
    ./git.nix
    ./gnupg.nix
    ./lf.nix
    ./less.nix
    ./ssh.nix
    ./tmux.nix
    ./zsh.nix
  ];

  home.sessionVariables = { COLORTERM = "truecolor"; };

  home.packages = with pkgs; [
    # nix
    cachix
    comma # Install and run programs by sticking a , before them
    nix-update
    nixpkgs-fmt
    nixos-shell
    manix

    ripgrep # Better grep
    fd # Better find
    httpie # Better curl
    rage
    sops
    zstd
  ];
}
