{ lib, inputs, outputs, ... }:

{
  imports = [ ./openssh.nix ./nix.nix ./zsh.nix ];

  home-manager = {
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs; };
    sharedModules = [ inputs.sops-nix.homeManagerModule ];
  };

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    config = { allowUnfree = true; };
  };
}
