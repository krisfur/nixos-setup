{ pkgs, ... }:

{
  # Flakes + new nix CLI.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Latest mainline kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Trim the boot menu: keep only the last few generations as entries instead
  # of one per rebuild. (Older generations still exist for `nixos-rebuild
  # --rollback` / GC; this only limits what's listed at boot.)
  boot.loader.systemd-boot.configurationLimit = 5;

  # Quiet the boot console so kernel/boot text doesn't bleed onto tty1 and
  # garble the greetd greeter (the "double lines" artifact).
  boot.kernelParams = [ "quiet" ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # Networking.
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  # localsend (from the old Sway setup's ufw rules).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "uk";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.power-profiles-daemon.enable = true;

  users.users.kfurman = {
    isNormalUser = true;
    description = "Krzysztof Furman";
    # Bootstrap password so you can log in after the first install. CHANGE IT
    # with `passwd` once logged in (this value is world-readable in the store).
    initialPassword = "changeme";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
      "docker"
    ];
    shell = pkgs.fish;
  };

  programs.fish.enable = true;

  nixpkgs.config.allowUnfree = true;
}
