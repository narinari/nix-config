# Hermes daily-podcast の配信用 nginx vhost
#
# Tailscale 内のみで podcast の RSS / mp3 / transcript を配信する。
# - listen は tailscale0 インターフェース (および localhost) に限定
# - autoindex は off (一覧露出させない)
# - /var/lib/hermes-podcast/episodes/ 配下を /podcasts/ にマウント
#
# iPhone から Pocket Casts などのアプリで http://khali/podcasts/<topic>/feed.xml
# を購読する想定。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  podcastRoot = "/var/lib/hermes-podcast/episodes";
in
{
  services.nginx = {
    enable = lib.mkDefault true;

    # MIME 型: mp3 / xml / txt は nginx default で十分だが念のため明示
    appendHttpConfig = ''
      types {
        audio/mpeg mp3;
        application/rss+xml xml;
        text/plain txt;
      }
    '';

    virtualHosts."khali-podcast" = {
      # Tailscale 内のみ到達可能にする。
      # khali の networking.firewall は tailscale0 を trustedInterfaces に入れていて、
      # それ以外のインターフェースは port 80 を許可していないので、0.0.0.0:80 で
      # listen していても Tailnet 外からは弾かれる (default ファイアウォールで足切り)。
      # FQDN は MagicDNS の `khali.taild10c60.ts.net`。Overcast などの podcast
      # クライアントは短いホスト名 (khali) を validation で弾くため FQDN を使う。
      serverName = "khali.taild10c60.ts.net";
      serverAliases = [ "khali" ];
      default = true;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
      ];

      locations = {
        "/podcasts/" = {
          alias = "${podcastRoot}/";
          extraConfig = ''
            autoindex off;
            add_header Cache-Control "public, max-age=3600";
            # podcast クライアントは byte-range を要求する
            add_header Accept-Ranges bytes;
          '';
        };

        # cover image など共通アセットは state dir 直下の static/ 配下から配信。
        # episodes/ とは別ツリーなので、トピック追加時にデータが汚れない。
        "/podcasts/static/" = {
          alias = "/var/lib/hermes-podcast/static/";
          extraConfig = ''
            autoindex off;
            add_header Cache-Control "public, max-age=86400";
          '';
        };

        "= /podcasts" = {
          return = "404";
        };

        "/" = {
          return = "404";
        };
      };
    };
  };

  # /var/lib/hermes-podcast/ を作って nginx ユーザに read を許可する
  systemd.tmpfiles.rules = [
    "d ${podcastRoot} 0755 hermes hermes -"
  ];

  # nginx ユーザを hermes グループに入れて、エピソード mp3 を読めるようにする
  users.users.${config.services.nginx.user}.extraGroups = [ "hermes" ];
}
