_:

{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        grace = 0;
      };

      background = [
        {
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }
      ];

      input-field = [
        {
          size = "200, 50";
          position = "0, -80";
          halign = "center";
          valign = "center";
          placeholder_text = "Password...";
          fade_on_empty = true;
        }
      ];
    };
  };
}
