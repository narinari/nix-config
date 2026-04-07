{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";

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

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
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
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-compat.follows = "deploy-rs/flake-compat";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
      my-secrets,
      emacs-overlay,
      deploy-rs,
      nixpkgs-firefox-darwin,
      ...
    }@inputs:

    let
      inherit (self) outputs;
      lib = nixpkgs.lib // home-manager.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = f: lib.genAttrs systems (sys: f (pkgsFor sys));
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      overlays = import ./overlays { inherit inputs outputs; };

      packages = forEachSystem (pkgs: (import ./pkgs { inherit pkgs; })) // {
        # OpenClaw LXCテンプレート生成
        x86_64-linux = (forEachSystem (pkgs: (import ./pkgs { inherit pkgs; }))).x86_64-linux // {
          openclaw-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = { inherit inputs; };
            modules = [ ./hosts/openclaw ];
          };
          jellyfin-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = { inherit inputs; };
            modules = [ ./hosts/jellyfin ];
          };
          rin-lxc = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "proxmox-lxc";
            specialArgs = {
              inherit inputs outputs;
              baseHostname = "rin";
            };
            modules = [ ./hosts/rin ];
          };
        };
      };

      devShells = forEachSystem (
        pkgs:
        import ./nix/shell.nix {
          inherit pkgs;
          checks = import ./nix/checks.nix {
            inherit pkgs;
            inherit (inputs) pre-commit-hooks deploy-rs;
          } pkgs.system;
        }
      );

      nixosConfigurations = {
        khali = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "khali";
          };
          system = "x86_64-linux";
          modules = [ ./hosts/khali ];
        };
        rin = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "rin";
          };
          system = "x86_64-linux";
          modules = [ ./hosts/rin ];
        };
        rpi4-base = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ./hosts/rpi4-base ];
        };
        jarvis = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ./hosts/jarvis ];
        };
        friday = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ./hosts/friday ];
        };
        jellyfin = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "x86_64-linux";
          modules = [ ./hosts/jellyfin ];
        };
        silk = nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs outputs;
            baseHostname = "";
          };
          system = "aarch64-linux";
          modules = [ ./hosts/silk ];
        };
      };

      darwinConfigurations =
        let
          system = "aarch64-darwin";
        in
        {
          FL4N2RD4TD = darwin.lib.darwinSystem {
            inherit system;
            modules = [ ./hosts/FL4N2RD4TD ];
            specialArgs = { inherit inputs outputs; };
          };
          K54TXK9ML7 = darwin.lib.darwinSystem {
            inherit system;
            modules = [ ./hosts/K54TXK9ML7 ];
            specialArgs = {
              inherit inputs outputs;
              baseHostname = "K54TXK9ML7";
            };
          };
        };

      homeConfigurations = {
        "narinari@work-ec2" = lib.homeManagerConfiguration {
          modules = [
            ./home-manager/narinari/work-ec2.nix
            inputs.sops-nix.homeManagerModule # home-manager only (nix on ubuntu)
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@rin" = lib.homeManagerConfiguration {
          modules = [
            ./home-manager/narinari/rin.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@FL4N2RD4TD" = lib.homeManagerConfiguration {
          modules = [
            ./home-manager/narinari/FL4N2RD4TD.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "aarch64-darwin";
          extraSpecialArgs = { inherit inputs outputs; };
        };
        "narinari@khali" = lib.homeManagerConfiguration {
          modules = [
            ./home-manager/narinari/khali.nix
            inputs.sops-nix.homeManagerModule
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
      };

      deploy = {
        # Deployment options applied to all nodes
        sshUser = "narinari";
        # User to which profile will be deployed.
        user = "root";
        sshOpts = [
          "-p"
          "22"
          "-F"
          "./etc/ssh.config"
        ];

        fastConnection = false;
        autoRollback = true;
        magicRollback = true;

        # Or setup cross compilation
        remoteBuild = true;

        nodes = {
          jarvis = {
            hostname = "jarvis";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.jarvis;
              autoRollback = false;
            };
          };
          friday = {
            hostname = "friday";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.friday;
              autoRollback = false;
            };
          };
          jellyfin = {
            hostname = "jellyfin.local";
            profiles.system = {
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.jellyfin;
            };
          };
          rin = {
            hostname = "rin.local";
            profiles.system = {
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.rin;
            };
          };
          silk = {
            hostname = "silk";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.silk;
              autoRollback = false;
            };
          };
        };
      };
    };
}
