flake:

[
  flake.inputs.home-manager.darwinModules.home-manager
  flake.inputs.agenix.darwinModules.default
] ++ flake.lib.loadModules ./modules
