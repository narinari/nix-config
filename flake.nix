{
  description = "My nix flake - orchestrator";

  inputs = {
    infra.url = "path:./infra";
    workstations.url = "path:./workstations";

    nixpkgs.follows = "workstations/nixpkgs";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      infra,
      workstations,
      deploy-rs,
      ...
    }@inputs:

    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (sys: f (pkgsFor sys));
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
    in
    {
      # Re-export from sub-flakes for nixos-rebuild / darwin-rebuild compatibility
      nixosConfigurations = infra.nixosConfigurations // workstations.nixosConfigurations;
      inherit (workstations) darwinConfigurations;
      homeConfigurations = infra.homeConfigurations // workstations.homeConfigurations;

      # Re-export overlays from workstations (tracks master)
      inherit (workstations) overlays;

      # Re-export packages from sub-flakes
      packages =
        let
          mergePkgs = sys: (infra.packages.${sys} or { }) // (workstations.packages.${sys} or { });
        in
        nixpkgs.lib.genAttrs systems mergePkgs;

      devShells = forEachSystem (
        pkgs:
        import ./nix/shell.nix {
          inherit pkgs;
          checks = import ./nix/checks.nix {
            inherit pkgs self;
            inherit (inputs) pre-commit-hooks deploy-rs;
          } pkgs.system;
        }
      );

      deploy = {
        sshUser = "narinari";
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
        remoteBuild = true;

        nodes = {
          jarvis = {
            hostname = "jarvis";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos infra.nixosConfigurations.jarvis;
              autoRollback = false;
            };
          };
          friday = {
            hostname = "friday";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos infra.nixosConfigurations.friday;
              autoRollback = false;
            };
          };
          jellyfin = {
            hostname = "jellyfin.local";
            profiles.system = {
              path = deploy-rs.lib.x86_64-linux.activate.nixos infra.nixosConfigurations.jellyfin;
            };
          };
          rin = {
            hostname = "rin.local";
            profiles.system = {
              path = deploy-rs.lib.x86_64-linux.activate.nixos infra.nixosConfigurations.rin;
            };
          };
          silk = {
            hostname = "silk";
            profiles.system = {
              path = deploy-rs.lib.aarch64-linux.activate.nixos infra.nixosConfigurations.silk;
              autoRollback = false;
            };
          };
        };
      };
    };
}
