{ pkgs, ... }:

{
  # GTK テーマ (GTK3 + GTK4/libadwaita)
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  # libadwaita (GTK4) ダークモード
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "adw-gtk3-dark";
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
