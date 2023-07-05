{ pkgs, ... }:

{
  home.packages = with pkgs; [
    k9s
    kdash
    kubectl
    kubectx
    kubelogin-oidc
    # istioctl
    kubernetes-helm
    kind
  ];
}
