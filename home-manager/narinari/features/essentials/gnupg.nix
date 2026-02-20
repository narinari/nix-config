{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.zsh.initContent = ''
    [[ -o interactive ]] && export GPG_TTY=$TTY
  '';

  programs.gpg = {
    enable = true;
    homedir = "${config.xdg.dataHome}/gnupg";
  };

  # Linux用: services.gpg-agentを使用（systemd統合）
  services.gpg-agent = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    enableExtraSocket = true;
    enableZshIntegration = true;
    pinentry.package = pkgs.pinentry-qt;
    defaultCacheTtl = 86400; # 1日
    maxCacheTtl = 86400; # 1日
    enableScDaemon = false;
  };
}
