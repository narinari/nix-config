{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cargo
    cargo-audit
    cargo-outdated
    # cargo-asm
    # cargo-bloat
    # cargo-crev
    cargo-expand
    cargo-flamegraph
    # cargo-fuzz
    # cargo-geiger
    cargo-sweep
    # cargo-tarpaulin # aarch64 not support
    cargo-udeps
  ];
}
