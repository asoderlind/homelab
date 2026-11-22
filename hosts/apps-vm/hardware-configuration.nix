# PLACEHOLDER: replace with nixos-generate-config output from the actual VM.
# Assumes an x86_64 Proxmox VM using UEFI and virtio storage.
{ lib, ... }:
{
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "virtio_blk" "ahci" "sd_mod" ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/REPLACE_WITH_VM_ROOT";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/REPLACE_WITH_VM_EFI";
    fsType = "vfat";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
