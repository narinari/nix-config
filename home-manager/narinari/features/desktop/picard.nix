# MusicBrainz Picard (音楽タガー)
#
# - タグ付け後のファイルは jarvis の Samba 共有 (/mnt/tanabe-media、
#   hosts/khali/default.nix で cifs automount) 配下の Musics に移動する。
#   同じ共有を Volumio も参照しているため、Volumio が見ているツリーの中では
#   タグ付けせず、khali ローカルの作業用ディレクトリ (inbox) に新規リップを置き、
#   Picard の保存で Musics へ移動する運用にする。作業後は Volumio 側で再スキャン。
# - Picard は終了時に Picard.ini を丸ごと書き戻す (QSettings) ため、
#   xdg.configFile で Nix store への symlink にすると read-only で保存に失敗する。
#   そのため初回 activation 時のみ seed し、以降は GUI での変更を尊重する。
#   設定を Nix 側で変えたい場合は Picard.ini を削除して再 activation する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  musicLibraryDir = "/mnt/tanabe-media/Musics";
  inboxDir = "${config.home.homeDirectory}/Music/picard-inbox";

  # QSettings IniFormat。Picard 2.x のキー名は picard/ui/options/{renaming,cover,general}.py
  # と picard/ui/filebrowser.py を参照。
  initialConfig = pkgs.writeText "picard-initial.ini" ''
    [setting]
    move_files=true
    move_files_to=${musicLibraryDir}
    rename_files=true
    delete_empty_dirs=true
    move_additional_files=true
    move_additional_files_pattern=*.jpg *.png *.log *.cue
    save_images_to_tags=true
    save_images_to_files=true
    cover_image_filename=cover
    save_only_one_front_image=true
    starting_directory=true
    starting_directory_path=${inboxDir}

    [persist]
    current_browser_path=${inboxDir}
  '';

  configFile = "${config.xdg.configHome}/MusicBrainz/Picard.ini";
in
{
  home.packages = [ pkgs.picard ];

  home.activation.picardInitialConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${inboxDir}"
    if [ ! -f "${configFile}" ]; then
      run mkdir -p "$(dirname "${configFile}")"
      run cp "${initialConfig}" "${configFile}"
      run chmod 644 "${configFile}"
    fi
  '';
}
