{ pkgs, lib, outputs, ... }:

{
  imports = [ ./kitty.nix ];

  home.packages = with pkgs; [
    feh # light-weight image viewer
    xdg-utils
    noto-fonts-cjk
    outputs.packages."${pkgs.system}".berkeley-mono
    outputs.packages."${pkgs.system}".berkeley-mono-nerdfonts
  ];

  home.sessionVariables = {
    EDITOR = "emacsclient -c -a emacs";
    VISUAL = "emacsclient -c -a emacs";
  };

  fonts.fontconfig.enable = true;
}
