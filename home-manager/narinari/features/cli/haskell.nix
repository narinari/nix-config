{ pkgs, ... }:

{
  home.packages = with pkgs; [ stack ];
}
