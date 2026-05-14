{ lib, ... }:

{
  # graphical-session.target は niri でも発火するが、hypridle は hyprland-lock-notify-v1
  # を要求する Hyprland 専用デーモン。niri セッションで起動しないよう env で gating。
  systemd.user.services.hypridle.Unit.ConditionEnvironment =
    lib.mkForce "HYPRLAND_INSTANCE_SIGNATURE";

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        #   {
        #     timeout = 300; # 5分アイドル → ロック
        #     on-timeout = "loginctl lock-session";
        #     on-resume = "";
        #   }
        #   {
        #     timeout = 330; # ロック後30秒 → ディスプレイオフ
        #     on-timeout = "hyprctl dispatch dpms off";
        #     on-resume = "hyprctl dispatch dpms on";
        #   }
        {
          timeout = 300; # 5分アイドル  → ディスプレイオフ
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
