{
  pkgs,
  config,
  ...
}:
{
  # launchdサービスを無効化（--supervisedモードの問題を回避）
  # home-managerのgpg-agent launchdサービスは--supervisedを使用するが、
  # これはsystemd用であり、launchdとの互換性問題でshell-initエラーが発生する
  services.gpg-agent.enable = false;

  # gpg-agent.confを手動設定（gpgのauto-start機能を利用）
  home.file."${config.programs.gpg.homedir}/gpg-agent.conf".text = ''
    pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
    default-cache-ttl 86400
    max-cache-ttl 86400
    enable-ssh-support
  '';
}
