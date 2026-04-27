{ config, lib, ... }:

{
  # パスワードなしsudo（wheelグループ）
  security.sudo.wheelNeedsPassword = false;

  # Prometheus node exporter（全サーバー共通）
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
    port = 9002;
    openFirewall = true;
  };

}
