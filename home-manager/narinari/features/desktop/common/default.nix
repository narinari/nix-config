{ pkgs, lib, outputs, ... }:

{
  home.packages = with pkgs; [
    feh # light-weight image viewer
    xdg-utils
    ./kitty.nix
  ];
}
