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

  fcitx-overlay =
    final: prev: if prev.stdenv.hostPlatform.isLinux then { fcitx-engines = final.fcitx5; } else { };
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

  # herdr 0.9.x (nixpkgs-unstable): zig 製の libghostty-vt を ld.bfd がリンクできず失敗する
  # (".eh_frame_hdr refers to overlapping FDEs")。lld でリンクする。
  # infra (nixos-unstable) の 0.7.1 はキャッシュ済みで壊れていないので触らない。
  herdr-overlay = final: prev: {
    herdr =
      if prev.stdenv.hostPlatform.isLinux && prev.lib.versionAtLeast prev.herdr.version "0.9" then
        prev.herdr.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [ final.lld ];
          env = (old.env or { }) // {
            RUSTFLAGS = "-C link-arg=-fuse-ld=lld";
          };
        })
      else
        prev.herdr;
  };

  # mycli: sqlglot 28.x との依存関係の問題を解消
  mycli-overlay = final: prev: {
    mycli = prev.mycli.overridePythonAttrs (old: {
      pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "sqlglot" ];
    });
  };
}
