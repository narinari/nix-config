{
  description = "Workstations - desktop and Darwin machines (nixpkgs master)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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

    nixpkgs-firefox-darwin = {
      url = "github:bandithedoge/nixpkgs-firefox-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprpanel = {
      url = "github:Jas-SinghFSU/HyprPanel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
      ...
    }@inputs:

    let
      inherit (self) outputs;
      lib = nixpkgs.lib // home-manager.lib;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (sys: f (pkgsFor sys));
    in
    {
      overlays = import ../overlays { inherit inputs outputs; };

      packages = forEachSystem (pkgs: import ../pkgs { inherit pkgs; });

      nixosConfigurations = {
        khali = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "khali";
          };
          system = "x86_64-linux";
          modules = [ ../hosts/khali ];
        };
      };

      darwinConfigurations = {
        hail-mary = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [ ../hosts/hail-mary ];
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "hail-mary";
          };
        };
      };

      homeConfigurations = {
        "narinari@khali" = lib.homeManagerConfiguration {
          modules = [
            ../home-manager/narinari/khali.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
      };
    };
}
