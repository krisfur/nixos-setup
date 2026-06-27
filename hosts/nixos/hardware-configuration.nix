{ lib, modulesPath, ... }:

# PLACEHOLDER - replace this entire file per machine.
#
# `nixos-generate-config` detects everything machine-specific (kernel modules,
# CPU microcode, kvm-amd vs kvm-intel, real filesystem UUIDs) and writes it
# here. Do that on the target machine during install (see README) and overwrite
# this file wholesale; don't hand-edit the values below.
#
# The defaults here only exist so the flake evaluates before you've generated
# the real config. They match the disk LABELs the README tells you to set when
# formatting (nixos + boot), so an install done exactly as documented would
# also work with this placeholder - but you should still generate the real one.

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT"; # FAT uppercases the label
    fsType = "vfat";
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
