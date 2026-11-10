# Hermes 用 Bitwarden (Password Manager) エージェントアカウントの基盤。
#
# 正本は narinari の Bitwarden vault。エージェントに任せるログインだけを
# Families org の collection `hermes-agent` に置き、エージェント専用アカウント
# (無料) にその collection だけを共有する。サイトごとのシークレットは複製しない。
#
# ここで供給するもの:
# - `bw` CLI (hermes の extraPackages)
# - hermes-bw-login.service: エージェントアカウントで `bw login --apikey` (未ログイン時のみ)
# - /run/agenix/hermes-bw-password: エージェントアカウントのマスターパスワード
#   (hermes 所有 0400)。利用側は HERMES_BW_PASSWORD_FILE で参照し、
#   `bw unlock --passwordfile` に渡す。
#
# 運用手順・残存リスクは docs/hermes-credential-vault.md を参照。
{
  config,
  inputs,
  pkgs,
  ...
}:

let
  hermesHome = "/var/lib/hermes";
  bw = "${pkgs.bitwarden-cli}/bin/bw";
in
{
  age.secrets = {
    # BW_CLIENTID / BW_CLIENTSECRET (エージェントアカウントの個人 API キー)。
    # hermes-bw-login.service の EnvironmentFile= でのみ使う (hermes 本体には渡さない)。
    "hermes-bw-agent-env" = {
      file = "${inputs.my-secrets}/private/hermes-bw-agent-env.age";
    };
    # エージェントアカウントのマスターパスワード (改行なし 1 行)。
    "hermes-bw-password" = {
      file = "${inputs.my-secrets}/private/hermes-bw-password.age";
      mode = "0400";
      owner = "hermes";
      group = "hermes";
    };
  };

  services.hermes-agent = {
    extraPackages = [ pkgs.bitwarden-cli ];
    environment.HERMES_BW_PASSWORD_FILE = config.age.secrets."hermes-bw-password".path;
  };

  # bw のデータ (暗号化 vault キャッシュ・ログイン状態) は
  # $HOME/.config/Bitwarden CLI に置かれる。HOME=/var/lib/hermes なので
  # hermes-agent の ReadWritePaths 内に収まる。
  systemd.services.hermes-bw-login = {
    description = "Log in the Hermes Bitwarden agent account (bw login --apikey)";
    wantedBy = [ "multi-user.target" ];
    before = [ "hermes-agent.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HOME = hermesHome;
      NO_COLOR = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "hermes";
      Group = "hermes";
      EnvironmentFile = config.age.secrets."hermes-bw-agent-env".path;
    };
    script = ''
      set -eu
      if ${bw} login --check --nointeraction >/dev/null 2>&1; then
        echo "[hermes-bw-login] already logged in; skipping"
        exit 0
      fi
      ${bw} login --apikey --nointeraction
    '';
  };
}
