# Hermes Agent plugin: family-inventory API (OpenAPI-driven thin HTTP wrapper).
#
# Distribution shape: directory-based plugin (matches Hermes's bundled plugin
# layout under share/hermes-agent/plugins/). Same approach as
# pkgs/hermes-claude-code-plugin/. The NixOS module's
# `services.hermes-agent.extraPlugins` symlinks this derivation into
# `${stateDir}/.hermes/plugins/nix-managed-family-inventory/` and Hermes
# discovers `plugin.yaml` + `register()` automatically on startup.
#
# Design principle: ZERO family-inventory domain knowledge lives here. The
# bundled openapi.yaml is the single source of truth; register() parses it at
# runtime and synthesizes one Hermes tool per OpenAPI operation. To pick up
# upstream API changes, run ./update-openapi.sh and rebuild.
{
  lib,
  runCommand,
}:

runCommand "hermes-family-inventory-plugin"
  {
    pname = "hermes-family-inventory-plugin";
    version = "0.1.0";

    meta = with lib; {
      description = "Hermes plugin that exposes the family-inventory agent API (OpenAPI-driven)";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
  ''
    install -d "$out"
    cp -r ${./src}/. "$out/"
  ''
