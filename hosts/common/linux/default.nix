{
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    ./locale.nix
    ./nix-optimizations.nix
    ./openssh.nix
    ./sops.nix
  ];

  #nix = {
  #  # TODO: temporary fix for NixOS/nix#7704
  #  package = pkgs.nixVersions.nix_2_12;
  #};

  environment = {
    # enableAllTerminfo = true は nixos/modules/config/terminfo.nix の固定リストを
    # 丸ごと引き込むが、gcc 16 移行でそのうち 2 つが上流でビルド不能になっている:
    #   - rxvt-unicode-unwrapped(-emoji): 独自 lerp が C++20 の std::lerp と衝突
    #     (nixpkgs#568896 / 未マージ PR #568978)
    #   - contour: vtbackend/Image.cpp が旧 std::simd 名 (native_simd 等) を使用
    #     (gcc 16 一括追跡: nixpkgs#569854)
    # どちらもバイナリキャッシュに無くローカルビルドで落ちるため、同リストから
    # この 2 つを除いたものを自前で列挙する。上流修正後は enableAllTerminfo に戻す。
    enableAllTerminfo = false;
    systemPackages = map (x: x.terminfo) (
      with pkgs.pkgsBuildBuild;
      [
        alacritty
        foot
        ghostty
        kitty
        mtm
        rio
        st
        tmux
        wezterm
        yaft
      ]
    );
    shells = with pkgs; [
      zsh
      bashInteractive
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # IPv6無効化（RTX810がEDNS非対応のため）
  networking.enableIPv6 = lib.mkDefault false;

  # Increase open file limit for sudoers
  security.pam.loginLimits = [
    {
      domain = "@wheel";
      item = "nofile";
      type = "soft";
      value = "524288";
    }
    {
      domain = "@wheel";
      item = "nofile";
      type = "hard";
      value = "1048576";
    }
  ];

  # targets.genericLinux.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
      addresses = true;
    };
  };
}
