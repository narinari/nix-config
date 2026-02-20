{
  pkgs,
  ...
}:
{
  services.gpg-agent = {
    enable = true;
    enableExtraSocket = true;
    enableZshIntegration = true;
    pinentry = {
      package = pkgs.pinentry_mac;
      program = "pinentry-mac";
    };
    defaultCacheTtl = 86400; # 1日
    maxCacheTtl = 86400; # 1日
    enableScDaemon = false;
  };
}
