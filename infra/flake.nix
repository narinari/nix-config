{
  description = "Infrastructure - home servers (nixos-unstable)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
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

    my-private-modules = {
      url = "git+ssh://git@github.com/narinari/nix-private-modules?ref=main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        my-secrets.follows = "my-secrets";
      };
    };

    nixpkgs-firefox-darwin = {
      url = "github:bandithedoge/nixpkgs-firefox-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
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
        "aarch64-linux"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (sys: f (pkgsFor sys));
    in
    {
      overlays = import ../overlays { inherit inputs outputs; };

      packages = forEachSystem (pkgs: import ../pkgs { inherit pkgs; }) // {
        x86_64-linux = (forEachSystem (pkgs: import ../pkgs { inherit pkgs; })).x86_64-linux // {
          openclaw-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = { inherit inputs; };
            modules = [ ../hosts/openclaw ];
          };
          jellyfin-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = { inherit inputs; };
            modules = [ ../hosts/jellyfin ];
          };
          rin-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = {
              inherit inputs outputs;
              baseHostname = "rin";
            };
            modules = [ ../hosts/rin ];
          };
        };
      };

      nixosConfigurations = {
        rin = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "rin";
          };
          system = "x86_64-linux";
          modules = [ ../hosts/rin ];
        };
        rpi4-base = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ../hosts/rpi4-base ];
        };
        jarvis = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ../hosts/jarvis ];
        };
        friday = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ../hosts/friday ];
        };
        jellyfin = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "x86_64-linux";
          modules = [ ../hosts/jellyfin ];
        };
        silk = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ../hosts/silk ];
        };
      };

      homeConfigurations = {
        "narinari@work-ec2" = lib.homeManagerConfiguration {
          modules = [
            ../home-manager/narinari/work-ec2.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@rin" = lib.homeManagerConfiguration {
          modules = [
            ../home-manager/narinari/rin.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
      };
    };
}
