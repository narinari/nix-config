{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        utils.follows = "flake-utils";
        flake-compat.follows = "flake-compat";
      };
    };

    flake-utils.url = "github:numtide/flake-utils";

    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  # add the inputs declared above to the argument attribute set
  outputs =
    { self, nixpkgs, home-manager, darwin, flake-utils, agenix, ... }@inputs:
    let inherit (self) outputs;
    in flake-utils.lib.eachDefaultSystem (system: {
      checks = import ./nix/checks.nix inputs system;

      devShells.default = import ./nix/dev-shell.nix inputs system;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.inputs.emacs-overlay.overlay ];
        config.allowUnfree = true;
        config.allowAliases = true;
      } // {
        inherit (agenix.packages.${system}) agenix;
      };
    }) // {
      darwinConfigurations."FL4N2RD4TD" = darwin.lib.darwinSystem {
        system = flake-utils.lib.system.aarch64-darwin;
        modules = [
          home-manager.darwinModules.home-manager
          agenix.darwinModules.default
          ./hosts/FL4N2RD4TD/default.nix
        ];
        pkgs = import nixpkgs {
          system = flake-utils.lib.system.aarch64-darwin;
          overlays = [ self.inputs.emacs-overlay.overlay ];
          config.allowUnfree = true;
          config.allowAliases = true;
        };
      };
    };
}
