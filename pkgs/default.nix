{ pkgs ? import <nixpkgs> { } }:

{
  fosi = pkgs.callPackage ./fosi { };
  lsec2 = pkgs.callPackage ./lsec2 { };
  berkeley-mono = pkgs.callPackage ./font-berkeley-mono { };
  berkeley-mono-nerdfonts = pkgs.callPackage ./font-berkeley-mono-nerdfonts { };
  ibm-plex-sans = pkgs.callPackage ./font-ibm-plex-sans { };
}
