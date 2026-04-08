_:

{
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "";
        before_sleep_cmd = "";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 300; # 5分
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}
