# VOICEVOX engine — Hermes daily-podcast plugin の音声合成バックエンド
#
# nixpkgs の `voicevox-engine` パッケージは存在するが NixOS モジュール化されて
# おらず、また公式 Docker イメージ (voicevox/voicevox_engine) の方が更新頻度・
# 対応プラットフォームに優位なので oci-containers 経由で動かす。
#
# port 50021 は localhost のみで listen させ、Tailscale 経由でアクセスさせない
# (hermes-agent が同ホスト同居なので 127.0.0.1 で十分)。
#
# 設計判断:
#   - CPU 版 (`cpu-latest`) を採用。Phase 2 で GPU 余りがあれば nvidia 版に差し替え。
#   - `--memory=4g` / `--cpus=4` で他サービスへの侵食を抑制。
#   - autoStart で boot 時 / rebuild 時に自動起動。
{
  config,
  lib,
  pkgs,
  ...
}:

{
  # podman backend を有効化 (既に他で有効ならべき等)
  virtualisation = {
    podman = {
      enable = lib.mkDefault true;
      dockerCompat = lib.mkDefault true;
    };
    oci-containers = {
      backend = lib.mkDefault "podman";
      containers.voicevox-engine = {
        image = "voicevox/voicevox_engine:cpu-latest";
        ports = [ "127.0.0.1:50021:50021" ];
        extraOptions = [
          "--memory=4g"
          "--cpus=4"
        ];
        autoStart = true;
      };
    };
  };

  # hermes-agent が VOICEVOX engine の起動待ちで失敗しないよう、systemd の依存を
  # 軽く貼っておく (oci-containers が生成する unit は podman-voicevox-engine.service)。
  systemd.services.hermes-agent.after = [ "podman-voicevox-engine.service" ];
  systemd.services.hermes-agent.wants = [ "podman-voicevox-engine.service" ];
}
