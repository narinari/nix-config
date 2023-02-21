{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ragenix = {
      url = "github:yaxitech/ragenix";
      inputs.flake-utils.follows = "flake-utils";
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
  outputs = { self, nixpkgs, home-manager, darwin, flake-utils, ... }@inputs:
    let system = "aarch64-darwin";
    in flake-utils.lib.eachDefaultSystem (system: {
      devShells.default = import ./nix/dev-shell.nix inputs system;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.inputs.emacs-overlay.overlay ];
        config.allowUnfree = true;
        config.allowAliases = true;
      };
    }) // {
      darwinConfigurations."FL4N2RD4TD" = darwin.lib.darwinSystem {
        inherit system;
        modules = [
          home-manager.darwinModules.home-manager
          ./hosts/FL4N2RD4TD/default.nix
        ];
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ self.inputs.emacs-overlay.overlay ];
          config.allowUnfree = true;
          config.allowAliases = true;
        };
      };
    };
}
