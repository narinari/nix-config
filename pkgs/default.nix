{ pkgs ? import <nixpkgs> { } }:

{
  fosi = pkgs.callPackage ./fosi { };
  lsec2 = pkgs.callPackage ./lsec2 { };
}
