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
    ./darwin
    ./features/desktop/common
  ];
}
