{ pkgs, lib, outputs, ... }:

{
  imports = [ ./kitty.nix ./wezterm.nix ];

  home.packages = with pkgs; [
    feh # light-weight image viewer
    xdg-utils
    noto-fonts-cjk
    outputs.packages."${pkgs.system}".berkeley-mono
    outputs.packages."${pkgs.system}".berkeley-mono-nerdfonts
    outputs.packages."${pkgs.system}".ibm-plex-sans
  ];

  home.sessionVariables = {
    EDITOR = "emacsclient -c -a emacs";
    VISUAL = "emacsclient -c -a emacs";
  };

  fonts.fontconfig.enable = true;
}
