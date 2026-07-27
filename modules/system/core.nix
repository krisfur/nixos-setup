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
  boot.loader.systemd-boot.configurationLimit = 3;

  # quiet: keeps kernel/boot text off tty1, which otherwise garbles the greetd
  # greeter (the "double lines" artifact).
  # pcie_aspm.policy: firmware never enables L1.2 on the NVMe and wifi links.
  # If this causes NVMe stalls or wifi drops, step down to "powersave".
  boot.kernelParams = [ "quiet" "pcie_aspm.policy=powersupersave" ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # Networking.
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # localsend (from the old Sway setup's ufw rules).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];

  # Pin the global regulatory domain to GB. This does not reach the ath11k
  # card: it is self-managed and keeps its firmware's US domain, logging a
  # harmless "failed to process regulatory info -22" at boot. 6 GHz works
  # regardless — that error is not fixable from the OS, so don't chase it.
  hardware.wirelessRegulatoryDatabase = true;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=GB
  '';

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "uk";

  hardware.bluetooth.enable = true;
  # Nothing pairs automatically, so leave the radio off until asked for.
  hardware.bluetooth.powerOnBoot = false;

  services.power-profiles-daemon.enable = true;

  # ppd 0.30's amdgpu actions store their on/off state in
  # /var/lib/power-profiles-daemon rather than in config, so re-assert both on
  # every start to stop the stateful toggles drifting. amdgpu_panel_power is
  # ABM, which dims the panel on power-saver; amdgpu_dpm tunes GPU clocks with
  # no visual effect. The leading "" clears the upstream ExecStart entry.
  systemd.services.power-profiles-daemon.serviceConfig = {
    ExecStart = [
      ""
      "${pkgs.power-profiles-daemon}/libexec/power-profiles-daemon"
    ];
    ExecStartPost = [
      "${pkgs.power-profiles-daemon}/bin/powerprofilesctl configure-action --enable amdgpu_dpm"
      "${pkgs.power-profiles-daemon}/bin/powerprofilesctl configure-action --enable amdgpu_panel_power"
    ];
  };

  # Auto-switch power profile on plug/unplug: performance on AC, power-saver
  # on battery. Runs once at boot for the initial state, then re-runs via the
  # udev rule below whenever the mains adapter changes state. Manual overrides
  # (waybar's profile cycler) stick until the next plug/unplug event.
  # Must hang off graphical.target, not multi-user.target: upstream ppd has
  # After=multi-user.target, so a multi-user-wanted unit that waits on ppd
  # (even implicitly via D-Bus activation) deadlocks boot until the 25s D-Bus
  # timeout and fails with an empty profile list.
  systemd.services.power-profile-on-ac = {
    description = "Set power profile based on AC state";
    wantedBy = [ "graphical.target" ];
    after = [ "power-profiles-daemon.service" ];
    wants = [ "power-profiles-daemon.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ "$(cat /sys/class/power_supply/AC/online)" = "1" ]; then
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
      else
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
      fi
    '';
  };
  # Match on type=Mains rather than the device name so this survives the
  # adapter enumerating under a different name. --no-block because udev RUN
  # handlers must not wait on other services.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${pkgs.systemd}/bin/systemctl start --no-block power-profile-on-ac.service"

    # Runtime PM defaults to off on every PCI device and ppd never sets it
    # (TLP would, but conflicts with ppd). "auto" lets drivers drop to D3 when
    # idle, which also parks the unused Realtek NIC; it resumes on carrier.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';

  # NM otherwise defers to the driver default, which leaves this off.
  networking.networkmanager.wifi.powersave = true;

  boot.kernel.sysctl = {
    # Per-core lockup-detector timer; only useful when debugging kernel hangs.
    "kernel.nmi_watchdog" = 0;
    # Fewer, larger writeback flushes so the NVMe reaches deep APST states.
    "vm.dirty_writeback_centisecs" = 1500;
  };

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
