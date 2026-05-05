_:

{
  # noctalia-shell (Quickshell ベースのデスクトップシェル)。
  # 設定は GUI / ~/.config/noctalia/ で運用するため、ここでは enable のみ。
  # workstations/flake.nix で inputs.noctalia.homeModules.default を読み込み済み。
  programs.noctalia-shell.enable = true;
}
