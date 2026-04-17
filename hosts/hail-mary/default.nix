{ pkgs, inputs, ... }:

{
  imports = [
    ../common/global
    ../common/darwin
    ../common/users/narinari
  ];

  networking = {
    hostName = "hail-mary";
  };

  # Tailscale (GUI アプリ) + Codex CLI (OpenAI コーディングエージェント)
  homebrew.casks = [
    "tailscale"
    "codex"
  ];

  system.stateVersion = 5;

  system.primaryUser = "narinari";

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
}
