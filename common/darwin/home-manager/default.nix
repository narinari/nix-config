{ pkgs, config, ... }:

{
  imports = [
    # ./copyApplications.nix
    ./gnupg.nix
    ./rust.nix
    ./xdg.nix
  ];

  home.packages = with pkgs; [
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
}
