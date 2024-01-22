{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "emacs-overlay/nixpkgs-stable";
        flake-utils.follows = "emacs-overlay/flake-utils";
      };
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "emacs-overlay/nixpkgs-stable";
      };
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        darwin.follows = "darwin";
        home-manager.follows = "home-manager";
      };
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    my-secrets = {
      url = "git+ssh://git@github.com/narinari/nix-secrets?ref=main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        agenix.follows = "agenix";
      };
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, my-secrets, emacs-overlay
    , ... }@inputs:

    let
      inherit (self) outputs;
      lib = nixpkgs.lib // home-manager.lib;
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forEachSystem = f: lib.genAttrs systems (sys: f pkgsFor.${sys});
      pkgsFor = nixpkgs.legacyPackages;
    in {
      overlays = import ./overlays { inherit inputs outputs; };

      packages = forEachSystem (pkgs: (import ./pkgs { inherit pkgs; }));

      devShells = forEachSystem (pkgs:
        import ./nix/shell.nix {
          inherit pkgs;
          checks = import ./nix/checks.nix {
            inherit pkgs;
            inherit (inputs) pre-commit-hooks;
          } pkgs.system;
        });

      nixosConfigurations = {
        rin = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [ ./hosts/rin ];
        };
      };

      darwinConfigurations = {
        FL4N2RD4TD = let system = "aarch64-darwin";
        in darwin.lib.darwinSystem {
          inherit system;
          modules = [ ./hosts/FL4N2RD4TD ];
          specialArgs = { inherit inputs outputs; };
        };
      };

      homeConfigurations = {
        "narinari@work-ec2" = lib.homeManagerConfiguration {
          modules = [
            ./home-manager/narinari/work-ec2.nix
            inputs.sops-nix.homeManagerModule # home-manager only (nix on ubuntu)
          ];
          pkgs = pkgsFor.x86_64-linux;
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@rin" = lib.homeManagerConfiguration {
          modules = [ ./home-manager/narinari/rin.nix ];
          pkgs = pkgsFor.x86_64-linux;
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@FL4N2RD4TD" = lib.homeManagerConfiguration {
          modules = [ ./home-manager/narinari/FL4N2RD4TD.nix ];
          pkgs = pkgsFor.aarch64-darwin;
          extraSpecialArgs = { inherit inputs outputs; };
        };
      };
    };
}
