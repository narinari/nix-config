# 朝夕 (07-08 / 18-19 時) の WAN 断がどの区間
# (RTX810 LAN / VDSL→NGN 端 / transix GW / AFTR / 外部) で起きるかを切り分けるための計測。
# friday の Prometheus から scrape される。
{ pkgs, ... }:

let
  # DNS 系 module の共通部分 (UDP で www.iij.ad.jp の A を引く)
  mkDnsModule = ipProtocol: {
    prober = "dns";
    timeout = "5s";
    dns = {
      query_name = "www.iij.ad.jp";
      query_type = "A";
      transport_protocol = "udp";
      preferred_ip_protocol = ipProtocol;
      ip_protocol_fallback = false;
    };
  };

  # HTTP 系 module の共通部分 (204 を返すエンドポイントへの GET)
  mkHttpModule = ipProtocol: {
    prober = "http";
    timeout = "5s";
    http = {
      preferred_ip_protocol = ipProtocol;
      ip_protocol_fallback = false;
      valid_status_codes = [ 204 ];
      method = "GET";
    };
  };

  blackboxConfig = (pkgs.formats.yaml { }).generate "blackbox.yml" {
    modules = {
      dns_v4 = mkDnsModule "ip4";
      dns_v6 = mkDnsModule "ip6";
      # RTX810 の DNS は EDNS 非対応なので rcode のみ検証する
      dns_rtx = mkDnsModule "ip4" // {
        dns = (mkDnsModule "ip4").dns // {
          valid_rcodes = [ "NOERROR" ];
        };
      };
      http_v4 = mkHttpModule "ip4";
      http_v6 = mkHttpModule "ip6";
    };
  };

  ifIndexLabel = [
    {
      labelname = "ifIndex";
      type = "gauge";
    }
  ];
  ifDescrLookup = [
    {
      labels = [ "ifIndex" ];
      labelname = "ifDescr";
      oid = "1.3.6.1.2.1.2.2.1.2";
      type = "DisplayString";
    }
  ];
  mkIfMetric = name: oid: type: {
    inherit name oid type;
    help = "${name} (IF-MIB)";
    indexes = ifIndexLabel;
    lookups = ifDescrLookup;
  };
  mkScalar = name: oid: {
    inherit name oid;
    type = "gauge";
    help = "${name} (YAMAHA-RT-HW-MIB)";
  };
in
{
  # friday の Prometheus から scrape (LAN は CGN 配下で外部到達不可)
  networking.firewall.allowedTCPPorts = [
    9002
    9374
    9115
    9116
  ];

  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9002;
      enabledCollectors = [ "systemd" ];
    };

    # ICMP 疎通・遅延の区間別計測 (モジュールが CAP_NET_RAW を付与済み)
    smokeping = {
      enable = true;
      port = 9374;
      pingInterval = "1s";
      hosts = [
        "192.168.100.1" # RTX810 LAN 側
        "2409:10:ae00:6400::fffe" # VDSL 越しの NGN 端ルーター (v6 tracepath 2 hop 目)
        "2404:8e00:feed:ff1c::2" # transix IPv6 ゲートウェイ
        "2404:8e00::feed:100" # transix AFTR (IPv6)
        "14.0.9.197" # AFTR の IPv4 側 (DS-Lite トンネル経由、v4 tracepath 2 hop 目)
        "1.1.1.1" # 外部 IPv4 (DS-Lite 経由)
        "8.8.8.8" # 外部 IPv4 (DS-Lite 経由)
        "2606:4700:4700::1111" # 外部 IPv6 (ネイティブ)
        "2001:4860:4860::8888" # 外部 IPv6 (ネイティブ)
      ];
    };

    # DNS / HTTP の v4・v6 別プローブ
    blackbox = {
      enable = true;
      port = 9115;
      configFile = blackboxConfig;
    };

    # RTX810 の SNMP (IF カウンタ / CPU / メモリ)
    snmp = {
      enable = true;
      port = 9116;
      configuration = {
        auths.yamaha_v2 = {
          community = "rtxmon";
          version = 2;
        };
        modules.yamaha = {
          # RTX810 は ifXTable (64bit カウンタ) 非対応なので ifTable の 32bit カウンタを使う
          # (100 Mbps で約 5.7 分ごとにラップするが 15s scrape の rate() で吸収できる)
          walk = [
            "1.3.6.1.2.1.2.2" # ifTable
          ];
          get = [
            "1.3.6.1.4.1.1182.2.1.4.0"
            "1.3.6.1.4.1.1182.2.1.5.0"
            "1.3.6.1.4.1.1182.2.1.6.0"
            "1.3.6.1.4.1.1182.2.1.7.0"
          ];
          metrics = [
            {
              name = "ifDescr";
              oid = "1.3.6.1.2.1.2.2.1.2";
              type = "DisplayString";
              help = "ifDescr (IF-MIB)";
              indexes = ifIndexLabel;
            }
            (mkIfMetric "ifOperStatus" "1.3.6.1.2.1.2.2.1.8" "gauge")
            (mkIfMetric "ifInDiscards" "1.3.6.1.2.1.2.2.1.13" "counter")
            (mkIfMetric "ifInErrors" "1.3.6.1.2.1.2.2.1.14" "counter")
            (mkIfMetric "ifOutDiscards" "1.3.6.1.2.1.2.2.1.19" "counter")
            (mkIfMetric "ifOutErrors" "1.3.6.1.2.1.2.2.1.20" "counter")
            (mkIfMetric "ifInOctets" "1.3.6.1.2.1.2.2.1.10" "counter")
            (mkIfMetric "ifOutOctets" "1.3.6.1.2.1.2.2.1.16" "counter")
            (mkScalar "yrhMemoryUtil" "1.3.6.1.4.1.1182.2.1.4")
            (mkScalar "yrhCpuUtil5sec" "1.3.6.1.4.1.1182.2.1.5")
            (mkScalar "yrhCpuUtil1min" "1.3.6.1.4.1.1182.2.1.6")
            (mkScalar "yrhCpuUtil5min" "1.3.6.1.4.1.1182.2.1.7")
          ];
        };
      };
    };
  };

  # RTX810 の syslog (UDP 514) を journald に取り込む
  services.udp514-journal = {
    enable = true;
    openFirewall = true;
  };
}
