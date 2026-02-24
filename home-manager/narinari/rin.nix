{
  inputs,
  outputs,
  config,
  pkgs,
  lib,
  ...
}:

let
  # ターミナル版Emacs（emacs-nox）+ tree-sitter
  terminalEmacs = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (
    epkgs: with epkgs; [
      vterm
      (treesit-grammars.with-grammars (
        p: with p; [
          tree-sitter-bash
          tree-sitter-c
          tree-sitter-dockerfile
          tree-sitter-elisp
          tree-sitter-go
          tree-sitter-gomod
          tree-sitter-haskell
          tree-sitter-json
          tree-sitter-markdown
          tree-sitter-nix
          tree-sitter-python
          tree-sitter-rust
          tree-sitter-toml
          tree-sitter-typescript
          tree-sitter-yaml
        ]
      ))
    ]
  );
in
{
  imports = [
    ./global
    ./features/cli
    ./features/llm
    ./features/terminal-access
  ];

  targets.genericLinux.enable = true;

  # Emacsをターミナル版に上書き（LXCでGUI不要）
  programs.emacs.package = lib.mkForce terminalEmacs;

  services = {
    syncthing.enable = true;
    systembus-notify.enable = true;
  };

  systemd.user.startServices = "sd-switch";
}
