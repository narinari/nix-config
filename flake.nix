{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-22.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
    };

    nix-packages = {
      url = "github:reckenrode/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-unstable-packages = {
      url = "github:reckenrode/nix-packages";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    my-secrets = {
      url = "git+file:./secrets";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.agenix.follows = "agenix";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, darwin, home-manager
    , home-manager-unstable, sops-nix, agenix, my-secrets, emacs-overlay, ...
    }@inputs:

    let inherit (self) outputs;
    in {
      overlays = { emacs-overlay = emacs-overlay.overlay; };

      homeConfigurations = {
        narinari = let
          system = "x86_64-linux";
          pkgs = nixpkgs.legacyPackages.${system} // {
            inherit (agenix.packages.${system}) agenix;
          };
        in home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [ ./home-manager/narinari/work-ec2.nix ];

          extraSpecialArgs = { inherit inputs outputs; };
        };
      };
    };
}
