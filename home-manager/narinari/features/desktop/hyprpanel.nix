{
  pkgs,
  inputs,
  ...
}:

{
  programs.hyprpanel = {
    enable = true;
    systemd.enable = true;
  };
}
