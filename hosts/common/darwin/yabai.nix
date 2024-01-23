{ config, lib, pkgs, ... }:

{
  services = {
    yabai = {
      enable = true;
      enableScriptingAddition = true;
      extraConfig = ''
        #!/usr/bin/env sh

        # global settings
        yabai -m config mouse_follows_focus          on
        yabai -m config focus_follows_mouse          on
        yabai -m config window_placement             second_child
        yabai -m config window_topmost               off
        yabai -m config window_shadow                on
        yabai -m config window_opacity               off
        yabai -m config window_opacity_duration      0.0
        yabai -m config active_window_opacity        1.0
        yabai -m config normal_window_opacity        0.90
        yabai -m config window_border                on
        yabai -m config window_border_width          1
        yabai -m config active_window_border_color   0xff775759
        yabai -m config normal_window_border_color   0xff555555
        yabai -m config insert_feedback_color        0xffd75f5f
        yabai -m config split_ratio                  0.50
        yabai -m config auto_balance                 off
        yabai -m config mouse_modifier               fn
        yabai -m config mouse_action1                move
        yabai -m config mouse_action2                resize

        # general space settings
        yabai -m config layout                       bsp
        yabai -m config top_padding                  0
        yabai -m config bottom_padding               0
        yabai -m config left_padding                 0
        yabai -m config right_padding                0
        yabai -m config window_gap                   02

        # float system preferences
        yabai -m rule --add app="^System Preferences$" manage=off
        yabai -m rule --add app="^システム環境設定$" manage=off
        yabai -m rule --add app="^システム設定$" manage=off
        yabai -m rule --add app="^Raycast$" manage=off

        # show digital colour meter topmost and on all spaces
        yabai -m rule --add app="^Digital Colou?r Meter$" sticky=on

        echo "yabai configuration loaded.."
      '';
    };

    skhd = {
      enable = true;
      skhdConfig = ''
        #------------------------------------------------------------
        # モニター操作
        #------------------------------------------------------------
        # モニターを選択する
        ctrl + cmd - j  : yabai -m display --focus next
        ctrl + cmd - k  : yabai -m display --focus prev

        # ウィンドウをモニターに移動する
        ctrl + cmd - 1  : yabai -m window --space 1; yabai -m space --focus 1
        ctrl + cmd - 2  : yabai -m window --space 2; yabai -m space --focus 2
        ctrl + cmd - 3  : yabai -m window --space 3; yabai -m space --focus 3

        #------------------------------------------------------------
        # ウィンドウの選択・操作
        #------------------------------------------------------------
        # ウィンドウを選択する
        alt - j : yabai -m window --focus prev
        alt - k : yabai -m window --focus next

        # ウィンドウを入れ替える
        ctrl + cmd - b : yabai -m window --swap west
        ctrl + cmd - n : yabai -m window --swap south
        ctrl + cmd - p : yabai -m window --swap north
        ctrl + cmd - f : yabai -m window --swap east

        # オフセット有無
        alt - a : yabai -m space --toggle padding; yabai -m space --toggle gap

        #------------------------------------------------------------
        # ウィンドウのサイズ調整
        #------------------------------------------------------------
        # ウィンドウサイズを全て等しくする
        shift + cmd - 0 : yabai -m space --balance

        # ウィンドウを移動する
        shift + ctrl - a : yabai -m window --move rel:-20:0
        shift + ctrl - s : yabai -m window --move rel:0:20
        shift + ctrl - w : yabai -m window --move rel:0:-20
        shift + ctrl - d : yabai -m window --move rel:20:0

        # ウィンドウのサイズを増やす
        shift + alt - a : yabai -m window --resize left:-20:0
        shift + alt - s : yabai -m window --resize bottom:0:20
        shift + alt - w : yabai -m window --resize top:0:-20
        shift + alt - d : yabai -m window --resize right:20:0

        # ウィンドウのサイズを減らす
        shift + cmd - a : yabai -m window --resize left:20:0
        shift + cmd - s : yabai -m window --resize bottom:0:-20
        shift + cmd - w : yabai -m window --resize top:0:20
        shift + cmd - d : yabai -m window --resize right:-20:0

        # set insertion point in focused container
        ctrl + alt - h : yabai -m window --insert west
        ctrl + alt - j : yabai -m window --insert south
        ctrl + alt - k : yabai -m window --insert north
        ctrl + alt - l : yabai -m window --insert east


        #------------------------------------------------------------
        # レイアウトの設定
        #------------------------------------------------------------
        # レイアウト変更
        ctrl + alt - b : yabai -m space --layout bsp
        ctrl + alt - f : yabai -m space --layout float

        # ----------------------------------------------------------
        #   float 時のレイアウト操作
        # ----------------------------------------------------------
        # ウィンドウを移動する(Float時のみ)
        #ctrl + cmd - b : yabai -m window --warp west
        #ctrl + cmd - n : yabai -m window --warp south
        #ctrl + cmd - p : yabai -m window --warp north
        #ctrl + cmd - f : yabai -m window --warp east


        # フルスクリーンにする
        shift + cmd - up     : yabai -m window --grid 1:1:0:0:1:1

        # 左半分にする
        shift + cmd - left   : yabai -m window --grid 1:2:0:0:1:1

        # 右半分にする
        shift + cmd - right  : yabai -m window --grid 1:2:1:0:1:1

        #------------------------------------------------------------
        #   bsp 時のレイアウト操作
        #------------------------------------------------------------
        # ウインドウの並びを回転する
        alt - r : yabai -m space --rotate 90

        # Y軸方向で反転する
        alt - y : yabai -m space --mirror y-axis

        # Y軸方向で反転する
        alt - x : yabai -m space --mirror x-axis

        # 親レイアウト方向で伸ばす
        shift + alt - d : yabai -m window --toggle zoom-parent

        # フルスクリーンにする
        shift + alt - f : yabai -m window --toggle zoom-fullscreen

        # 縦分割にする
        shift + alt - e : yabai -m window --toggle split

        # 画面中央に表示する
        alt - t : yabai -m window --toggle float; \\
                  yabai -m window --grid 12:12:1:1:10:10

        # focus window
        # alt - h : yabai -m window --focus west

        # swap managed window
        # shift + alt - h : yabai -m window --swap north

        # move managed window
        # shift + cmd - h : yabai -m window --warp east

        # balance size of windows
        # shift + alt - 0 : yabai -m space --balance

        # make floating window fill screen
        # shift + alt - up     : yabai -m window --grid 1:1:0:0:1:1

        # make floating window fill left-half of screen
        # shift + alt - left   : yabai -m window --grid 1:2:0:0:1:1

        # create desktop, move window and follow focus - uses jq for parsing json (brew install jq)
        # shift + cmd - n : yabai -m space --create && \\
        #                   index="$(yabai -m query --spaces --display | jq 'map(select(."native-fullscreen" == 0))[-1].index')" && \\
        #                   yabai -m window --space "\$\{index}" && \\
        #                   yabai -m space --focus "\$\{index}"

        # fast focus desktop
        # cmd + alt - x : yabai -m space --focus recent
        # cmd + alt - 1 : yabai -m space --focus 1

        # send window to desktop and follow focus
        # shift + cmd - z : yabai -m window --space next; yabai -m space --focus next
        # shift + cmd - 2 : yabai -m window --space  2; yabai -m space --focus 2

        # focus monitor
        # ctrl + alt - z  : yabai -m display --focus prev
        # ctrl + alt - 3  : yabai -m display --focus 3

        # send window to monitor and follow focus
        # ctrl + cmd - c  : yabai -m window --display next; yabai -m display --focus next
        # ctrl + cmd - 1  : yabai -m window --display 1; yabai -m display --focus 1

        # move floating window
        # shift + ctrl - a : yabai -m window --move rel:-20:0
        # shift + ctrl - s : yabai -m window --move rel:0:20

        # increase window size
        # shift + alt - a : yabai -m window --resize left:-20:0
        # shift + alt - w : yabai -m window --resize top:0:-20

        # decrease window size
        # shift + cmd - s : yabai -m window --resize bottom:0:-20
        # shift + cmd - w : yabai -m window --resize top:0:20

        # set insertion point in focused container
        # ctrl + alt - h : yabai -m window --insert west

        # toggle window zoom
        # alt - d : yabai -m window --toggle zoom-parent
        # alt - f : yabai -m window --toggle zoom-fullscreen

        # toggle window split type
        # alt - e : yabai -m window --toggle split

        # float / unfloat window and center on screen
        # alt - t : yabai -m window --toggle float; \\
        #           yabai -m window --grid 4:4:1:1:2:2

        # toggle sticky(+float), topmost, picture-in-picture
        # alt - p : yabai -m window --toggle sticky; \\
        #           yabai -m window --toggle topmost; \\
        #           yabai -m window --toggle pip
      '';
    };
  };
}
