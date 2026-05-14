{
  pkgs,
  inputs,
  lib,
  ...
}:

{
  programs.hyprpanel = {
    enable = true;
    systemd.enable = true;
  };

  # graphical-session.target は niri でも発火する。Hyprland 専用バー (gjs から
  # Hyprland IPC に接続) を niri セッションで起動しないよう、Hyprland 起動時のみ
  # 真になる HYPRLAND_INSTANCE_SIGNATURE で gating する。
  systemd.user.services.hyprpanel.Unit.ConditionEnvironment =
    lib.mkForce "HYPRLAND_INSTANCE_SIGNATURE";
}
