{ lib, inputs, outputs, ... }:

{
  imports = [ ./nix.nix ./zsh.nix ];

  home-manager = {
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs; };
  };

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    config = { allowUnfree = true; };
  };
}
