{ pkgs, config, lib, ... }: {
  # Nix configuration ------------------------------------------------------------------------------
  nix = {
    settings = {
      substituters = [ "https://cache.nixos.org/" ];
      trusted-public-keys =
        [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];

      trusted-users = [ "@admin" ];
    };

    configureBuildUsers = true;

    # Enable experimental nix command and flakes
    # nix.package = pkgs.nixUnstable;
    extraOptions = ''
      auto-optimise-store = true
      experimental-features = nix-command flakes
    '' + lib.optionalString (pkgs.system == "aarch64-darwin") ''
      extra-platforms = x86_64-darwin aarch64-darwin
    '';
  };

  # Make sure the nix daemon always runs
  services.nix-daemon.enable = true;

  # Installs a version of nix, that dosen't need "experimental-features = nix-command flakes" in /etc/nix/nix.conf
  #services.nix-daemon.package = pkgs.nixFlakes;

  # if you use zsh (the default on new macOS installations),
  # you'll need to enable this so nix-darwin creates a zshrc sourcing needed environment changes
  programs.zsh.enable = true;
  # bash is enabled by default

  # Apps
  # `home-manager` currently has issues adding them to `~/Applications`
  # Issue: https://github.com/nix-community/home-manager/issues/1341
  environment.systemPackages = with pkgs; [ terminal-notifier ];

  programs.nix-index.enable = true;

  # Fonts
  fonts.fontDir.enable = true;
  fonts.fonts = with pkgs; [
    recursive
    (nerdfonts.override { fonts = [ "SpaceMono" ]; })
  ];

  # Keyboard
  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = true;

  # Add ability to used TouchID for sudo authentication
  # security.pam.enableSudoTouchIdAuth = true;

  homebrew = {
    onActivation = {
      enable = true;
      autoUpdate = true;
    };

    taps = [ "goldeneggg/lsec2" "koekeishiya/formulae" ];

    brews = [
      "automake"
      "coreutils"
      "asdf"
      "mecab"
      "yadm"
      "goldeneggg/lsec2/lsec2"
      {
        name = "koekeishiya/formulae/skhd";
        start_service = true;
        restart_service = "changed";
      }
      {
        name = "koekeishiya/formulae/yabai";
        start_service = true;
        restart_service = "changed";
      }
    ];

    casks = [
      "keycastr"
      "the-unarchiver"
      "aquaskk"
      "xquartz"
      "bestres"
      "google-chrome"
      "licecap"
      "contexts"
      "iterm2"
      "raycast"
      "firefox"
      "karabiner-elements"
      "skitch"
    ];
  };

  system.defaults.dock = {
    autohide = true;
    orientation = "right";
  };

  # Secrets
  age = {
    identityPaths = [
      "/Users/narinari/.ssh/id_ed25519"
      "/Users/narinari/.ssh/narinari.t/id_ed25519"
    ];
  };
  users.users.narinari = {
    name = "narinari";
    home =
      "/Users/narinari"; # need only on macos https://github.com/LnL7/nix-darwin/issues/423
    shell = lib.mkIf config.programs.zsh.enable pkgs.zsh;
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    verbose = true;
  };
  home-manager.users.narinari = { imports = [ ./core ./dev ]; };
}
