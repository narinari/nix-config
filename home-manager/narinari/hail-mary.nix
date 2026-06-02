{
  inputs,
  outputs,
  consig,
  pkgs,
  ...
}:

{
  imports = [
    ./global
    ./features/cli
    ./features/llm
    ./features/llm/aperture.nix
    ./features/llm/codex.nix
    ./features/llm/claude-code-skills.nix
    ./darwin
    ./features/desktop/common
  ];
}
