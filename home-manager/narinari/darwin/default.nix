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

    karabiner-elements
    iterm2
    # xquartz

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
