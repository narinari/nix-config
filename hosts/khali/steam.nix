_:

{
  # Steam の前提条件 (allowUnfree / hardware.graphics.enable32Bit / video,audio グループ) は
  # それぞれ ../common/global, ./default.nix, ../common/users/narinari で既に有効。
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  # Feral GameMode。ゲームの launch options に `gamemoderun %command%` を指定して使う。
  programs.gamemode.enable = true;
}
