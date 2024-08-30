{ pkgs, ... }:

{
  home.packages = with pkgs; [
    k9s
    # kdash # 2024/08/27 build error
    kubectl
    kubectx
    kubelogin-oidc
    # istioctl
    kubernetes-helm
    kind
  ];
}
