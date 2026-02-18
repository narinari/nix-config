{
  pkgs,
  lib,
  config,
  ...
}:

{
  home.activation = {
    cleanUpGpgAgent = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent
    '';
  };
  services.gpg-agent = {
    enable = true;
    enableExtraSocket = true;
    enableZshIntegration = true;
    pinentry = {
      package = pkgs.pinentry_mac;
      program = "pinentry-mac";
    };
  };

  # home.file."${config.programs.gpg.homedir}/gpg-agent.conf".text = ''
  #   pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
  # '';
}
