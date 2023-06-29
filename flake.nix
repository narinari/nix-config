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

      darwinConfigurations = {
        FL4N2RD4TD = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [ ./hosts/FL4N2RD4TD ];
          specialArgs = { inherit inputs outputs; };
        };
      };

      homeConfigurations = {
        "narinari@work-dev" = lib.homeManagerConfiguration {
          modules = [ ./home-manager/narinari/work-ec2.nix ];
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
