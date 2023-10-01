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

  # #  xcbuild-overlay = final: prev: {
  # #    xcbuild = prev.xcbuild.override {
  # #      stdenv = prev.stdenv // {
  # #        targetPlatform = prev.stdenv.targetPlatform // {
  # #          xcodeVer = "13.4";
  # #          darwinSdkVersion = "13.4";
  # #        };
  # #      };
  # #    };
  # # };
  # lima-overlay = final: prev: {
  #   lima = prev.lima.override {
  #     # xcbuild = final.xcbuild;
  #     xcbuild = prev.xcbuild.override {
  #       stdenv = prev.stdenv // {
  #         targetPlatform = prev.stdenv.targetPlatform // {
  #           xcodeVer = "13.4";
  #           darwinSdkVersion = "13.4";
  #         };
  #       };
  #     };
  #     stdenv = prev.stdenv // {
  #       targetPlatform = prev.stdenv.targetPlatform // {
  #         xcodeVer = "13.4";
  #         darwinSdkVersion = "13.4";
  #       };
  #     };
  #   };
  # };
}
