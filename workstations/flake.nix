{
  description = "Workstations - desktop and Darwin machines (nixpkgs master)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin";
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

    # v5 は alpha (TOML 設定・ネイティブ実装) のため安定版 v4.7.7 (Quickshell 版) にピン。
    # programs.noctalia-shell + JSON 設定 (~/.config/noctalia/settings.json) を提供する。
    noctalia = {
      url = "github:noctalia-dev/noctalia/v4.7.7";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # tarball download (github: type) は repo サイズ (~173MB) で truncate するため
    # git+https を使用して shallow clone を許可する
    hermes-agent = {
      url = "git+https://github.com/NousResearch/hermes-agent?ref=refs/tags/v2026.8.31&submodules=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        # 上流 v2026.8.31 が nix/checks.nix 専用に home-manager input を追加したため、
        # follows を付けて二重の home-manager / nixpkgs が lock に入るのを防ぐ。
        home-manager.follows = "home-manager";
      };
    };
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
          modules = [
            ../hosts/khali
            inputs.agenix.nixosModules.default
          ];
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
            inputs.agenix.homeManagerModules.default
            inputs.noctalia.homeModules.default
          ];
          pkgs = pkgsFor "x86_64-linux";
          extraSpecialArgs = { inherit inputs outputs; };
        };
      };
    };
}
