{ pkgs, ... }:

{
  virtualisation = {
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        # OVMF は最近の nixpkgs で qemu に同梱されたため、専用 submodule は不要。
        # XML 側で <os firmware='efi'> を使うと libvirt が自動で適切な OVMF を選ぶ。
      };
      onBoot = "ignore";
      onShutdown = "shutdown";
    };
    spiceUSBRedirection.enable = true;
  };

  programs.virt-manager.enable = true;
}
