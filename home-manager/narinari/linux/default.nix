{ pkgs, ... }: {
  home.packages = with pkgs; [
    google-chrome # linux only

    # gimp
    # mediainfo
    # pavucontrol

    strace # linux only

    # compsize
    # xdragon
    # killall

    # remote
    # remmina # linux only
    # anydesk # linux only
    # rustdesk # linux only

    perf
    # sysstat

    # freeplane # mindmap linux only
  ];

  service.gpg-agent.enable = true;
}
