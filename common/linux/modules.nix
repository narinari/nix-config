flake:

[
  flake.inputs.home-manager.nixosModules.home-manager
  flake.inputs.agenix.nixosModules.default
] ++ flake.lib.loadModules ../shared/modules
