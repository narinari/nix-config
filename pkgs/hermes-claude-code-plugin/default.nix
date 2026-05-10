# Hermes Agent plugin: delegate complex design / review tasks to Claude Code.
#
# Distribution shape: directory-based plugin (matches Hermes's bundled plugin
# layout under share/hermes-agent/plugins/). The NixOS module's
# `services.hermes-agent.extraPlugins` symlinks this derivation into
# `${stateDir}/.hermes/plugins/nix-managed-claude-code/` and Hermes discovers
# `plugin.yaml` + `register()` automatically on startup.
#
# Why directory-style instead of an entry-point Python package: Hermes treats
# both as first-class but the directory form has no pyproject / build-system
# dependency, so it stays trivial to reason about in Nix.
{
  lib,
  runCommand,
}:

runCommand "hermes-claude-code-plugin"
  {
    pname = "hermes-claude-code-plugin";
    version = "0.1.0";

    meta = with lib; {
      description = "Hermes plugin that delegates design tasks to Claude Code";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
  ''
    install -d "$out"
    cp -r ${./src}/. "$out/"
  ''
