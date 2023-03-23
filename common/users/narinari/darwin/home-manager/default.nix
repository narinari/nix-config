{ pkgs, ... }:

{
  imports = [
    ./dock.nix
    # ./finder.nix
    # ./keyboard.nix
    # ./safari.nix
    ./ui.nix
  ];

  home.packages = with pkgs; [
    lima

    karabiner-elements
    iterm2
    # xquartz
  ];
}
