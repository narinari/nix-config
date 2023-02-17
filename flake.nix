{
  description = "My first nix flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-22.11-darwin";

    flake-utils.url = "github:numtide/flake-utils";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "flake-utils";
    };
    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };
  
  # add the inputs declared above to the argument attribute set
  outputs = { self, nixpkgs, home-manager, darwin, flake-utils, ... }: 
    {
      darwinConfigurations."FL4N2RD4TD" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          home-manager.darwinModules.home-manager
          ./hosts/FL4N2RD4TD/default.nix
          {
            nixpkgs.overlays = [ (import self.inputs.emacs-overlay) ];
          }
        ];
      };
    }
    // flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" ] (localSystem: {
      pkgs = import nixpkgs {
        inherit localSystem;
        overlays = [
          self.inputs.emacs-overlay
        ];
        config.allowUnfree = true;
        config.allowAliases = true;
      };
    });
}
