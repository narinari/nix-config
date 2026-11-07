# PLaMo 3 Translate 8B によるローカル翻訳 (khali 専用)。
#
# - plamo-llama-server: llama-server の user service。RTX 2080 は PRIME offload
#   構成なので nvidia-offload 経由で起動し、アイドル時はモデルを解放して VRAM を空ける
# - plamo-html: 英語混じりの HTML を日本語化する CLI (pkgs/plamo-html)
# - plamo-translate-html: 上記を呼ぶ Claude Code Skill
#
# 詳細は docs/plamo-translate.md。
{
  pkgs,
  lib,
  ...
}:

let
  # 既定の cudaCapabilities は 10 世代分のカーネルをビルドして非常に遅いので、
  # RTX 2080 (TU104) の 7.5 だけに絞る
  gpuPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      cudaSupport = true;
      cudaCapabilities = [ "7.5" ];
    };
  };

  plamoHtml = pkgs.callPackage ../../../../pkgs/plamo-html { };

  modelFile = "plamo-3-translate-8b-Q4_K_M.gguf";
  modelSha256 = "47a04e86a67bcc352fa186f01159060aae594b73993e1d49dbfc0ef0081d01ad";
  modelUrl = "https://huggingface.co/pfnet/plamo-3-translate-8b-GGUF/resolve/main/${modelFile}";

  # 5GB あるので Nix store には入れず、初回起動時に取得してハッシュを検証する
  fetchModel = pkgs.writeShellScript "plamo-fetch-model" ''
    set -euo pipefail
    dir="$1"
    target="$dir/${modelFile}"
    [ -f "$target" ] && exit 0
    ${pkgs.coreutils}/bin/mkdir -p "$dir"
    ${pkgs.curl}/bin/curl -fL --retry 3 -C - -o "$target.part" "${modelUrl}"
    echo "${modelSha256}  $target.part" | ${pkgs.coreutils}/bin/sha256sum -c -
    ${pkgs.coreutils}/bin/mv "$target.part" "$target"
  '';

  skillFile = ./claude/skills/plamo-translate-html/SKILL.md;
in
{
  home.packages = [ plamoHtml ];

  systemd.user.services.plamo-llama-server = {
    Unit = {
      Description = "llama-server for PLaMo 3 Translate 8B";
      After = [ "network-online.target" ];
    };
    Service = {
      # モデルが未取得だと初回はダウンロードに時間がかかる
      TimeoutStartSec = "1h";
      ExecStartPre = "${fetchModel} %h/.cache/plamo-translate/models";
      ExecStart = lib.concatStringsSep " " [
        "/run/current-system/sw/bin/nvidia-offload"
        "${gpuPkgs.llama-cpp}/bin/llama-server"
        "-m %h/.cache/plamo-translate/models/${modelFile}"
        "-c 16384"
        "-ngl 99"
        "-np 1"
        "--host 127.0.0.1"
        "--port 8000"
        "--alias plamo-3-translate"
        "--jinja"
        "--no-prefill-assistant"
        "--sleep-idle-seconds 300"
      ];
      Restart = "on-failure";
      RestartSec = "30s";
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.activation.claudePlamoTranslateHtmlSkill = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    skill_dir="$HOME/.claude/skills/plamo-translate-html"
    run mkdir -p "$skill_dir"
    run cp -f "${skillFile}" "$skill_dir/SKILL.md"
    run chmod 644 "$skill_dir/SKILL.md"
  '';
}
