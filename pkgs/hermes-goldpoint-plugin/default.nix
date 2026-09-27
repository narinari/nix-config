# Hermes Agent plugin: goldpoint-meisai
#
# GOLD POINT CARD+ (ヨドバシ) の利用明細CSVを毎月自動取得し、Google Drive の
# 家計/goldpoint/YYYY-MM.csv にアップロードする。ログインは headless Chromium +
# CDP (websockets) で実ブラウザ相当のフォーム入力を行い、認証情報は Bitwarden
# Secrets Manager (bws CLI) から実行時に取得する (モデルには渡らない)。
#
# 配布形態は directory-based plugin。hosts/khali/hermes-agent.nix の
# `services.hermes-agent.extraPlugins` 経由で
# `${stateDir}/.hermes/plugins/nix-managed-goldpoint/` に symlink され、
# Hermes が plugin.yaml + register() を発見してロードする。
#
# 追加 Python 依存 (websockets, google-api-python-client, google-auth-oauthlib,
# google-auth-httplib2) は hermes-agent NixOS モジュール側で extraPythonPackages
# 経由で供給する。bws バイナリと chromium は extraPackages 経由。詳細は本
# パッケージ README.md を参照。
{
  lib,
  runCommand,
}:

runCommand "hermes-goldpoint-plugin"
  {
    pname = "hermes-goldpoint-plugin";
    version = "0.1.0";

    meta = with lib; {
      description = "Hermes plugin that fetches GOLD POINT CARD+ statement CSVs and uploads them to Google Drive";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
  ''
    install -d "$out"
    cp -r ${./src}/. "$out/"
  ''
