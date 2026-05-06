{ config, pkgs, ... }:

{
  # GTK テーマ (GTK3 + GTK4/libadwaita) とアイコン
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    # GTK4 にも GTK3 と同じテーマを当てる (home-manager の legacy default を明示)
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
  };

  # libadwaita (GTK4) ダークモード + Qt/Quickshell から見える icon-theme
  # Quickshell (Qt6 QIconLoader) は GSettings の icon-theme を参照する
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "adw-gtk3-dark";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Adwaita";
    };
  };

  # Qt テーマ (qt5ct/qt6ct + Kvantum)
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style = {
      name = "kvantum";
      package = pkgs.kdePackages.qtstyleplugin-kvantum;
    };
  };

  xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
    [General]
    theme=KvArcDark
  '';

  home.packages = with pkgs; [
    libsForQt5.qtstyleplugin-kvantum # Qt5 用
  ];
}
