{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = "darwin";
      inputs.home-manager.follows = "home-manager";
    };

    nix-packages = {
      url = "github:reckenrode/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    my-secrets = {
      url = "git+ssh://github.com.private/narinari/nix-secrets?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.agenix.follows = "agenix";
    };
  };

  outputs = { self, nixpkgs, darwin, home-manager, my-secrets, emacs-overlay
    , ... }@inputs:

    let
      inherit (self) outputs;
      forEachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ];
      forEachPkgs = f: forEachSystem (sys: f nixpkgs.legacyPackages.${sys});

      mkNixos = modules:
        nixpkgs.lib.nixosSystem {
          inherit modules;
          specialArgs = { inherit inputs outputs; };
        };

      mkDarwin = system: modules:
        darwin.lib.darwinSystem {
          inherit system modules;
          specialArgs = { inherit inputs outputs; };
        };

      mkHome = modules: pkgs:
        home-manager.lib.homeManagerConfiguration {
          inherit modules pkgs;
          extraSpecialArgs = { inherit inputs outputs; };
        };
    in {
      overlays = import ./overlays { inherit inputs outputs; };

      devShells = forEachPkgs (pkgs:
        import ./nix/shell.nix {
          inherit pkgs;
          checks = import ./nix/checks.nix {
            inherit pkgs;
            inherit (inputs) pre-commit-hooks;
          } pkgs.system;
        });

      darwinConfigurations = {
        FL4N2RD4TD = mkDarwin "aarch64-darwin" [ ./hosts/FL4N2RD4TD ];
      };

      homeConfigurations = {
        "narinari@work-dev" = mkHome [ ./home-manager/narinari/work-ec2.nix ]
          nixpkgs.legacyPackages."x86_64-linux";
        "narinari@FL4N2RD4TD" =
          mkHome [ ./home-manager/narinari/FL4N2RD4TD.nix ]
          nixpkgs.legacyPackages."aarch64-darwin";
      };
    };
}
