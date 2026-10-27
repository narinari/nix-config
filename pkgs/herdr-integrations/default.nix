# herdr の agent integration (状態通知フック) をビルド時に生成する。
#
# `herdr integration install <agent>` は ~/.claude/settings.json などを直接書き換えるが、
# それらは home-manager / NixOS module が管理していて switch のたびに上書きされる。
# そこで空の HOME で install を走らせ、生成されたスクリプト / plugin だけを取り出す。
# フックの登録 (settings.json / config.toml / plugins.enabled) は各 nix 側で宣言する:
#   - claude: home-manager/narinari/features/llm/default.nix
#   - codex:  home-manager/narinari/features/llm/codex.nix
#   - hermes: hosts/khali/hermes-agent.nix
# 生成物にホスト固有のパスは含まれない (herdr 0.9.1 で確認)。
{
  runCommand,
  herdr,
}:

let
  generated = runCommand "herdr-integrations-${herdr.version}" { nativeBuildInputs = [ herdr ]; } ''
    export HOME="$TMPDIR/home"
    export HERMES_HOME="$HOME/.hermes"
    mkdir -p "$HOME/.claude" "$HOME/.codex" "$HERMES_HOME"
    for agent in claude codex hermes; do
      herdr integration install "$agent"
    done

    install -Dm755 "$HOME/.claude/hooks/herdr-agent-state.sh" "$out/claude/herdr-agent-state.sh"
    install -Dm755 "$HOME/.codex/herdr-agent-state.sh" "$out/codex/herdr-agent-state.sh"
    cp -r "$HERMES_HOME/plugins/herdr-agent-state" "$out/hermes"
  '';
in
{
  inherit generated;

  # services.hermes-agent.extraPlugins 用 (ルートに plugin.yaml が必要)
  hermesPlugin = runCommand "herdr-agent-state" { } ''
    cp -r ${generated}/hermes "$out"
  '';
}
