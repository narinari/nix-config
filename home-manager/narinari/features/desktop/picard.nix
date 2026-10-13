# MusicBrainz Picard (音楽タガー)
#
# - タグ付け後のファイルは jarvis の Samba 共有 (/mnt/tanabe-media、
#   hosts/khali/default.nix で cifs automount) 配下の Musics に移動する。
# - Picard は終了時に Picard.ini を丸ごと書き戻す (QSettings) ため、
#   xdg.configFile で Nix store への symlink にすると read-only で保存に失敗する。
#   そのため初回 activation 時のみ seed し、以降は GUI での変更を尊重する。
#   保存先を Nix 側で変えたい場合は Picard.ini を削除して再 activation する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  musicLibraryDir = "/mnt/tanabe-media/Musics";

  # QSettings IniFormat。Picard 2.x のキー名は picard/ui/options/renaming.py を参照。
  initialConfig = pkgs.writeText "picard-initial.ini" ''
    [setting]
    move_files=true
    move_files_to=${musicLibraryDir}
    rename_files=true
  '';

  configFile = "${config.xdg.configHome}/MusicBrainz/Picard.ini";
in
{
  home.packages = [ pkgs.picard ];

  home.activation.picardInitialConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -f "${configFile}" ]; then
      run mkdir -p "$(dirname "${configFile}")"
      run cp "${initialConfig}" "${configFile}"
      run chmod 644 "${configFile}"
    fi
  '';
}
