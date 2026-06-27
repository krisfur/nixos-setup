{ ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/system/core.nix
    ../../modules/system/desktop.nix
    ../../modules/system/dev.nix
    ../../modules/system/packages.nix
  ];

  networking.hostName = "nixos";

  # The release this config was first written against. Do not bump casually;
  # it controls stateful defaults (databases, etc.), not package versions.
  system.stateVersion = "25.05";
}
