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
        utils.follows = "utils";
        flake-compat.follows = "flake-compat";
      };
    };

    # flake-utils.url = "github:numtide/flake-utils";
    utils.url = "github:gytis-ivaskevicius/flake-utils-plus";

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
      inputs.utils.follows = "utils";
    };

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "utils";
    };

    my-secrets = {
      url = "path:./secrets";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # add the inputs declared above to the argument attribute set
  outputs = { self, nixpkgs, home-manager, darwin, utils, agenix, my-secrets
    , ... }@inputs:
    let
      inherit (self) outputs;
      inherit (nixpkgs.lib) recursiveUpdate;

      lib = import ./lib;
      # packages = import ./pkgs;
    in utils.lib.mkFlake rec {
      inherit self inputs lib;

      channelsConfig = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
      };

      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];

      sharedOverlays = [ self.inputs.emacs-overlay.overlay ];

      hostDefaults.modules = [ ./common/configuration.nix ];

      hosts = lib.mkHosts {
        inherit self;
        hostsPath = ./hosts;
      };

      outputsBuilder = channels: rec {
        checks = import ./nix/checks.nix {
          pkgs = channels.nixpkgs;
          inherit (inputs) pre-commit-hooks deploy-rs;
        } channels.nixpkgs.system;
        devShell = import ./nix/dev-shell.nix {
          pkgs = channels.nixpkgs // {
            inherit (agenix.packages.${channels.nixpkgs.system}) agenix;
          };
          inherit checks;
        } channels.nixpkgs.system;
        #   packages =
        #     let
        #       inherit (channels.nixpkgs.stdenv.hostPlatform) system;
        #     in
        #     packages { inherit lib channels; };
      };
    };

}
