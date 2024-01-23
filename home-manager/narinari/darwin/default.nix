{ pkgs, config, ... }:

{
  imports = [
    # ./copyApplications.nix
    ./gnupg.nix
    ./rust.nix
    ./xdg.nix
    ./ui.nix
    ./dock.nix
  ];

  home.packages = with pkgs; [
    lima

    iterm2
    # xquartz
    raycast

    bzip2
    coreutils
    curl
    diffutils
    findutils
    gnutar
    gzip
    less
    time
    darwin.trash
    unzip
    zip
    zstd
  ];

  # home.homeDirectory = "/home/${config.home.username}";
}
