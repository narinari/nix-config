# qBittorrent (BitTorrent クライアント)
#
# - 回線は transix (DS-Lite) のため IPv4 は CGN 配下でポート開放不可 (passive のみ)。
#   IPv6 (NGN 直通 IPoE) で connectable にする。RTX810 側の設定手順は
#   docs/rtx810-ipv6-qbittorrent-runbook.md を参照。
# - WebUI (8080) は Tailscale 経由のみ: firewall で開けず、tailscale0 が
#   trustedInterfaces に入っているため tailnet 内 + localhost からだけ届く
#   (podcast-nginx.nix と同じ方式)。
# - serverConfig を指定すると service 起動毎に qBittorrent.conf が Nix 生成版で
#   上書きされる (WebUI から変えた設定は再起動で消える)。永続化したい設定は
#   全てここに書くこと。
_:
let
  torrentPort = 50413;
  downloadDir = "/var/lib/qBittorrent/downloads";
in
{
  # common/linux の mkDefault false (RTX810 の EDNS 非対応対策) を上書き。
  # khali の DNS は systemd-resolved + 1.1.1.1 直でルーター非経由のため影響なし。
  networking.enableIPv6 = true;

  services.qbittorrent = {
    enable = true;
    torrentingPort = torrentPort;
    webuiPort = 8080;
    # openFirewall は webuiPort まで TCP で開けてしまい、かつ torrentingPort の
    # UDP を開けないため使わない (下の networking.firewall で手動指定)。
    extraArgs = [ "--confirm-legal-notice" ];
    serverConfig = {
      LegalNotice.Accepted = true;
      BitTorrent.Session = {
        DefaultSavePath = downloadDir;
        Port = torrentPort;
        # DS-Lite CGN の NAT セッション枯渇対策: 同時接続を控えめに
        MaxConnections = 200;
        MaxConnectionsPerTorrent = 60;
        MaxUploads = 20;
        MaxUploadsPerTorrent = 5;
      };
      Preferences.WebUI = {
        Address = "*";
        # 到達経路が tailnet + localhost に限定されているため認証免除にする
        # (パスワードハッシュを repo にコミットしないで済む)
        AuthSubnetWhitelistEnabled = true;
        AuthSubnetWhitelist = "100.64.0.0/10, 127.0.0.0/8";
        LocalHostAuth = false;
      };
    };
  };

  # torrent ポートのみ開放 (IPv4/IPv6 両方に適用される)。WebUI 8080 は開けない。
  networking.firewall = {
    allowedTCPPorts = [ torrentPort ];
    allowedUDPPorts = [ torrentPort ]; # DHT / uTP
  };

  # ダウンロード先。setgid でグループを qbittorrent に固定し、
  # narinari (common/users で qbittorrent グループに参加) が読み書きできるようにする。
  systemd.tmpfiles.rules = [
    "d ${downloadDir} 2775 qbittorrent qbittorrent -"
  ];
}
