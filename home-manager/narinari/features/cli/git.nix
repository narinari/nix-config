{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bfg-repo-cleaner
    gitAndTools.git-absorb
    gitAndTools.gitui
    gitAndTools.git-machete
    gitAndTools.git-secrets
    git-filter-repo
    gitAndTools.gh
    colordiff
    delta
    tcpdump
    ghq
    gst
  ];
}
