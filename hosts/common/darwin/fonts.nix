{ pkgs, ... }:

{
  fonts.packages = with pkgs; [ nerd-fonts.space-mono ];
}
