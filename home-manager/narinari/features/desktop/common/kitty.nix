{ config, lib, pkgs, ... }: {
  programs.kitty = {
    enable = true;
    font = {
      name = "BerkeleyMono Nerd Font";
      size = 11;
    };
    settings = { macos_option_as_alt = true; };
    keybindings = {
      "alt+0" = "send_text all \\x1b0";
      "alt+1" = "send_text all \\x1b1";
      "alt+2" = "send_text all \\x1b2";
      "alt+3" = "send_text all \\x1b3";
      "alt+4" = "send_text all \\x1b4";
      "alt+5" = "send_text all \\x1b5";
      "alt+6" = "send_text all \\x1b6";
      "alt+7" = "send_text all \\x1b7";
      "alt+8" = "send_text all \\x1b8";
      "alt+9" = "send_text all \\x1b9";

      "alt+a" = "send_text all \\x1ba";
      "alt+b" = "send_text all \\x1bb";
      "alt+c" = "send_text all \\x1bc";
      "alt+d" = "send_text all \\x1bd";
      "alt+e" = "send_text all \\x1be";
      "alt+f" = "send_text all \\x1bf";
      "alt+g" = "send_text all \\x1bg";
      "alt+h" = "send_text all \\x1bh";
      "alt+i" = "send_text all \\x1bi";
      "alt+j" = "send_text all \\x1bj";
      "alt+k" = "send_text all \\x1bk";
      "alt+l" = "send_text all \\x1bl";
      "alt+m" = "send_text all \\x1bm";
      "alt+n" = "send_text all \\x1bn";
      "alt+o" = "send_text all \\x1bo";
      "alt+p" = "send_text all \\x1bp";
      "alt+q" = "send_text all \\x1bq";
      "alt+r" = "send_text all \\x1br";
      "alt+s" = "send_text all \\x1bs";
      "alt+t" = "send_text all \\x1bt";
      "alt+u" = "send_text all \\x1bu";
      "alt+v" = "send_text all \\x1bv";
      "alt+w" = "send_text all \\x1bw";
      "alt+x" = "send_text all \\x1bx";
      "alt+y" = "send_text all \\x1by";
      "alt+z" = "send_text all \\x1bz";

      "alt+/" = "send_text all \\x1b/";
      "alt+;" = "send_text all \\x1b;";
      "alt+backslash" = "send_text all \\x1b\\x5c";
      "alt+space" = "send_text all \\x1b\\x20";

      "ctrl+tab" = "send_text all \\x11\\x0C";
      "shift+ctrl+tab" = "send_text all \\x11\\x08";
    };
    extraConfig = ''
      symbol_map U+3041-U+30FC,U+4EDD,U+3400-U+4DB5,U+4E00-U+9FCB,U+F900-U+FA6A,U+2E80-U+2FD5,U+FF5F-U+FF9F,U+3000-U+303F,U+31F0-U+31FF,U+3220-U+3243,U+3280-U+337F,U+FF01-U+FF5E Noto Sans CJK JP
    '';
  };
}
