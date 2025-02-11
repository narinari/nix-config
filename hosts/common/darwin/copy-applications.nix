{
  config,
  lib,
  pkgs,
  ...
}:

{
  system.activationScripts.applications.text = lib.mkForce ''
    echo "Setting up /Applications/Nix Apps" >&2
    appsSrc="${config.system.build.applications}/Applications/"
    baseDir="/Applications/Nix Apps"
    mkdir -p "$baseDir"
    ${pkgs.rsync}/bin/rsync --archive --checksum --chmod=-w --copy-unsafe-links --delete "$appsSrc" "$baseDir"
  '';
}
