{ pkgs, ... }:

{
  # Nix リモートビルダー用ユーザー
  users.users.builder = {
    isSystemUser = true;
    group = "builder";
    shell = pkgs.bash;
    openssh.authorizedKeys.keyFiles = [ ./builder_ed25519.pub ];
  };
  users.groups.builder = { };

  # builder を Nix の信頼済みユーザーに追加
  nix.settings.trusted-users = [ "builder" ];
}
