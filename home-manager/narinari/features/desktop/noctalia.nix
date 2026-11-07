_:

{
  # noctalia v5 (ネイティブ実装のデスクトップシェル)。
  # パッケージは nixpkgs の pkgs.noctalia、モジュールは home-manager 標準を使う。
  # flake input にしないことで GL ライブラリがシステムのドライバと同じ nixpkgs に揃う。
  #
  # 設定変更フロー:
  #   - 恒久設定は noctalia.toml に書き、nixos-rebuild switch で反映する。
  #     ビルド時に `noctalia config validate` が走る。
  #   - GUI での変更は ~/.local/state/noctalia/settings.toml に保存され、ファイルより優先される。
  #     noctalia.toml の変更が効かないときはこのファイルを確認する。
  #   - 実際に効いている設定は `noctalia config export` で確認できる。
  programs.noctalia = {
    enable = true;
    settings = ./noctalia.toml;
  };
}
