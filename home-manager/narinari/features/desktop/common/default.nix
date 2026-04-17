{
  pkgs,
  lib,
  outputs,
  ...
}:

{
  imports = [
    ./firefox.nix
    ./wezterm.nix
  ];

  home.packages = with pkgs; [
    feh # light-weight image viewer
    xdg-utils
    noto-fonts-cjk-sans
    outputs.packages."${pkgs.system}".berkeley-mono
    outputs.packages."${pkgs.system}".berkeley-mono-nerdfonts
    outputs.packages."${pkgs.system}".sf-mono
    outputs.packages."${pkgs.system}".sf-mono-nerdfonts
    outputs.packages."${pkgs.system}".ibm-plex-sans
    outputs.packages."${pkgs.system}".moralerspace-hw-nerdfonts
  ];

  home.sessionVariables = {
    EMACS = "emacsclient -c -a emacs";
    EDITOR = "emacsclient -c -a emacs";
    VISUAL = "emacsclient -c -a emacs";
  };

  fonts.fontconfig.enable = true;
}
