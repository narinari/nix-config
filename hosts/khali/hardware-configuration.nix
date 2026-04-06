# このファイルはターゲットマシンで以下のコマンドを実行して生成したものに置き換えること:
#   nixos-generate-config --root /mnt
# 生成されたファイルを hosts/khali/hardware-configuration.nix にコピーして
# by-uuid 形式のデバイスパスを確認・調整すること。
#
# Bus ID の確認方法:
#   lspci | grep -E "VGA|3D"
#   例: "00:02.0 VGA compatible controller: Intel ..." → intelBusId = "PCI:0:2:0"
#       "01:00.0 3D controller: NVIDIA ..."           → nvidiaBusId = "PCI:1:0:0"
{ config, lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ]; # AMD CPU の場合は kvm-amd に変更
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"; # ★ 要変更
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/XXXX-XXXX"; # ★ 要変更 (vfat ESP の UUID)
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # AMD CPU の場合: hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
