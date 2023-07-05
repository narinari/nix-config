{ outputs, inputs }:

{
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}' or
  flake-inputs = final: _: {
    inputs = builtins.mapAttrs (_: flake:
      (flake.packages or flake.legacyPackages or { }).${final.system} or { })
      inputs;
  };

  fcitx-overlay = final: prev:
    if prev.stdenv.isLinux then { fcitx-engines = final.fcitx5; } else { };
  emacs-overlay = inputs.emacs-overlay.overlay;
}
