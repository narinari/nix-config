{ pkgs, lib, outputs, ... }:

{
  imports = [ ./kitty.nix ];

  home.packages = with pkgs; [
    feh # light-weight image viewer
    xdg-utils
  ];

  sessionVariables = { VISUAL = "emacsclient"; };
}
