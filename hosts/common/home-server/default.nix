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

  # IPv6無効化（RTX810がEDNS非対応のため）
  networking.enableIPv6 = false;
}
