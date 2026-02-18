{
  pkgs,
  config,
  outputs,
  ...
}:
let
  claude-notification-subscriber = pkgs.writeShellScript "claude-notification-subscriber.sh" ''
    while true; do
      nc -l 60000 | while read line; do
        logger -t "claude-notification-subscriber" -p user.info "$line"
        osascript -e "$line"
      done
      sleep 1
    done
  '';
in
{
  imports = [
    # ./copyApplications.nix
    ./gnupg.nix
    ./rust.nix
    ./xdg.nix
    ./ui.nix
    ./dock.nix
    ./karabiner-elements.nix
  ];

  home.packages = with pkgs; [
    colima

    iterm2
    # xquartz
    raycast

    slack

    bzip2
    coreutils
    curl
    diffutils
    findutils
    gnutar
    gzip
    less
    time
    darwin.trash
    unzip
    zip
    zstd
  ];

  # home.homeDirectory = "/home/${config.home.username}";

  launchd.agents = {
    claude-notification-subscriber = {
      enable = true;
      config = {
        ProgramArguments = [ "${claude-notification-subscriber}" ];
        ProcessType = "Background";
        RunAtLoad = true;
        KeepAlive = true;
      };
    };
  };
}
