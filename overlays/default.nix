{ outputs, inputs }:

{
  # For every flake input, aliases 'pkgs.inputs.${flake}' to
  # 'inputs.${flake}.packages.${pkgs.system}' or
  # 'inputs.${flake}.legacyPackages.${pkgs.system}' or
  flake-inputs = final: _: {
    inputs = builtins.mapAttrs (
      _: flake: (flake.packages or flake.legacyPackages or { }).${final.system} or { }
    ) inputs;
  };

  fcitx-overlay = final: prev: if prev.stdenv.isLinux then { fcitx-engines = final.fcitx5; } else { };
  emacs-overlay = inputs.emacs-overlay.overlay;
  # nixpkgs-firefox-darwinのoverlayは古い形式(self: super:)なのでラップ
  nixpkgs-firefox-darwin = final: prev: inputs.nixpkgs-firefox-darwin.overlay final prev;

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

  # ollama: macOS で Metal GPU バックエンドを有効化
  ollama-metal-overlay =
    final: prev:
    if prev.stdenv.hostPlatform.isDarwin then
      {
        ollama = prev.ollama.overrideAttrs (old: {
          preBuild =
            builtins.replaceStrings
              [ "cmake -B build" ]
              [ "cmake -B build -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON" ]
              old.preBuild;
        });
      }
    else
      { };

  # mycli: sqlglot 28.x との依存関係の問題を解消
  mycli-overlay = final: prev: {
    mycli = prev.mycli.overridePythonAttrs (old: {
      pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "sqlglot" ];
    });
  };
}
