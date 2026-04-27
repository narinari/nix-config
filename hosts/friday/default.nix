{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}:

let
  mediaRoot = "/mnt/tanabe-media";
  epgstation-scripts = pkgs.callPackage ../../pkgs/epgstation-scripts { };
in
{
  imports = [
    ../rpi4-base
    ../common/home-server
    ../common/linux/nix-builder.nix
  ];

  networking = {
    hostName = "friday";
  };

  # jarvisのSamba共有をマウント
  fileSystems."${mediaRoot}" = {
    device = "//jarvis.local/tanabe-media";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in
      [
        "${automount_opts},iocharset=utf8,uid=epgstation,gid=epgstation,guest,nosetuids,noperm,rw"
      ];
  };

  services = {
    # EPGStation（テレビ録画サーバー）
    epgstation = {
      enable = true;
      openFirewall = true;
      usePreconfiguredStreaming = false;
      database.passwordFile = config.sops.secrets.epgstation-db-password.path;
      settings = {
        recorded = [
          {
            name = "recorded";
            path = "${mediaRoot}/Movies/recorded";
          }
        ];
        recordedTmp = "/var/lib/epgstation/recorded";
        recordedFormat = "%YEAR%%MONTH%%DAY%_%HOUR%%MIN%-%TITLE%";
        stream = import ../../modules/services/epgstation/streaming.nix;
        mirakurunPath = "http://silk.local:40772";
        encode = [
          {
            name = "H.264 default";
            cmd = "%NODE% ${epgstation-scripts}/encode/enc.js";
            suffix = ".mp4";
          }
          {
            name = "H.264 sw";
            cmd = "%NODE% ${epgstation-scripts}/encode/enc.js --software-encode";
            suffix = ".mp4";
          }
        ];
      };
    };

    mirakurun.enable = false;

    # Prometheus（メトリクス収集）
    prometheus = {
      enable = true;
      port = 9001;
      scrapeConfigs = [
        {
          job_name = "local exporter";
          static_configs = [
            {
              targets = [
                "jarvis.local:9002"
                "friday.local:9002"
                "silk.local:9002"
                "jarvis.local:${toString config.services.prometheus.exporters.smartctl.port}"
              ];
            }
          ];
        }
      ];
    };

    # Grafana（ダッシュボード）
    grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          domain = "friday.local";
          root_url = "http://friday.local/grafana/";
          serve_from_sub_path = true;
        };
        security.secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
      };
    };

    # Nginx（リバースプロキシ）
    nginx = {
      enable = true;
      virtualHosts."friday.local" = {
        locations."/grafana/" = {
          proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };

  # sops secrets
  sops.secrets.epgstation-db-password = {
    sopsFile = "${inputs.my-secrets}/private/service_secrets.yaml";
    owner = "epgstation";
    group = "wheel";
    mode = "0664";
  };

  sops.secrets.grafana-secret-key = {
    sopsFile = "${inputs.my-secrets}/private/service_secrets.yaml";
    owner = "grafana";
  };

  # IPv4優先設定
  environment.etc = {
    "gai.conf".text = ''
      precedence ::ffff:0:0/96  60
    '';
  };

  # epgstationユーザーをvideoグループに追加
  users.extraGroups.video.members = [ "epgstation" ];

  # ファイアウォール
  networking.firewall.allowedTCPPorts = [
    80 # nginx
    9001 # prometheus
  ];

  system.stateVersion = "23.11";
}
