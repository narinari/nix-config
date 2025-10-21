{
  pkgs ? import <nixpkgs> { },
}:

{
  fosi = pkgs.callPackage ./fosi { };
  lsec2 = pkgs.callPackage ./lsec2 { };
  berkeley-mono = pkgs.callPackage ./font-berkeley-mono { };
  berkeley-mono-nerdfonts = pkgs.callPackage ./font-berkeley-mono-nerdfonts { };
  sf-mono = pkgs.callPackage ./font-sf-mono { };
  sf-mono-nerdfonts = pkgs.callPackage ./font-sf-mono-nerdfonts { };
  ibm-plex-sans = pkgs.callPackage ./font-ibm-plex-sans { };
  moralerspace-hw-nerdfonts = pkgs.callPackage ./font-moralerspace-hw-nerdfonts { };
  run-in-tmux-popup = pkgs.callPackage ./run-in-tmux-popup { };
}
