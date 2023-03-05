{ pkgs, ... }:

{
  home.packages = with pkgs; [
    lima

    karabiner-elements
    iterm2
    # xquartz
  ];
}
