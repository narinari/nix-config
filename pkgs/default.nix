{ pkgs ? import <nixpkgs> { } }:

{
  fosi = pkgs.callPackage ./fosi { };
}
