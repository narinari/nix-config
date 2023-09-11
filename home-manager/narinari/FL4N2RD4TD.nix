{ inputs, outputs, consig, pkgs, ... }:

{
  imports = [
    inputs.sops-nix.homeManagerModule
    ./global
    ./work
    ./darwin
    ./features/desktop/common
  ];
}
