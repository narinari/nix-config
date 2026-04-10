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
    ./darwin
    ./features/desktop/common
  ];
}
