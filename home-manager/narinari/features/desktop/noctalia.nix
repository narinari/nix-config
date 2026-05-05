_:

{
  # noctalia-shell (Quickshell ベースのデスクトップシェル)。
  # workstations/flake.nix で inputs.noctalia.homeModules.default を読み込み済み。
  # 設定は GUI でエクスポートした noctalia.json を宣言的に取り込む。
  # 設定変更フロー:
  #   1. noctalia GUI で設定を変更
  #   2. Settings > Export で JSON を取得し noctalia.json に上書き保存
  #   3. nixos-rebuild switch
  programs.noctalia-shell = {
    enable = true;
    settings = builtins.fromJSON (builtins.readFile ./noctalia.json);
  };
}
