# Hermes Agent plugin: hermes-daily-podcast
#
# 毎日トピックごとに SNS / フィードを巡回 → LLM 採点と日本語要約 → VOICEVOX で音声化 →
# Tailscale 内 nginx で podcast RSS 配信 するパイプライン。tool として
# generate_daily_episode / list_topics / add_topic / list_episodes /
# regenerate_episode を Hermes に公開する。
#
# 配布形態は directory-based plugin。hosts/khali/hermes-agent.nix の
# `services.hermes-agent.extraPlugins` 経由で
# `${stateDir}/.hermes/plugins/nix-managed-daily-podcast/` に symlink され、
# Hermes が plugin.yaml + register() を発見してロードする。
#
# 追加 Python 依存 (httpx, feedparser, feedgen, trafilatura, rapidfuzz,
# url-normalize, atproto, jinja2, pydub) は hermes-agent NixOS モジュール側で
# extraPythonPackages 経由で供給する。詳細は本パッケージ README.md と
# hosts/khali/hermes-agent.nix を参照。
{
  lib,
  runCommand,
}:

runCommand "hermes-daily-podcast-plugin"
  {
    pname = "hermes-daily-podcast-plugin";
    version = "0.1.0";

    meta = with lib; {
      description = "Hermes plugin that produces a daily Japanese podcast from SNS / feed digests";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
  ''
    install -d "$out"
    cp -r ${./src}/. "$out/"
  ''
