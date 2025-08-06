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
    inputs.my-private-modules.homeManagerModules.work
    ./darwin
    ./features/desktop/common
  ];
}
