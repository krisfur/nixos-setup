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

  # Quiet the boot console so kernel/boot text doesn't bleed onto tty1 and
  # garble the greetd greeter (the "double lines" artifact).
  # pcie_aspm.policy: the BIOS default leaves link power management to
  # firmware, which on this board never enables L1.2 on the NVMe and wifi
  # links. powersupersave lets the kernel pick the deepest state each link
  # advertises. If this ever causes NVMe stalls or wifi drops, drop back to
  # "powersave" (L1 only, no L1.2 substates) before removing it entirely.
  boot.kernelParams = [ "quiet" "pcie_aspm.policy=powersupersave" ];
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
  # Don't power the radio at boot — nothing pairs automatically here, so it
  # otherwise sits enabled and idle. `bluetoothctl power on` (or the tray)
  # brings it up on demand.
  hardware.bluetooth.powerOnBoot = false;

  services.power-profiles-daemon.enable = true;

  # ppd 0.30 ships optional amdgpu actions whose on/off state lives in
  # /var/lib/power-profiles-daemon, not in config, so pin them here instead of
  # letting the stateful toggles drift.
  #
  # amdgpu_panel_power (ABM) is on trial: it was previously blocked outright
  # because it visibly dims the panel on power-saver, which is this machine's
  # default unplugged state. We're now letting it run to find out whether the
  # dimming is actually bothersome in practice. TO REVERT: put
  # `--block-action amdgpu_panel_power` back on the ExecStart line below and
  # drop it from the ExecStartPost --enable list.
  #
  # amdgpu_dpm (GPU clock tuning, no visual effect) stays enabled either way.
  # The leading "" in ExecStart clears the upstream unit's entry before
  # replacing it.
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

    # PCI runtime power management. Every device on this machine came up with
    # power/control=on, i.e. runtime PM disabled — power-profiles-daemon
    # doesn't touch this (TLP and `powertop --auto-tune` do, but TLP conflicts
    # with ppd and we keep ppd for the AC/battery profile switching above).
    # "auto" lets each driver drop its device to D3 when idle and resume on
    # demand; this is also what parks the built-in Realtek NIC, which
    # otherwise keeps its PHY powered whenever the interface is up with no
    # cable. Ethernet still works — r8169 resumes on carrier detect.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{power/control}="auto"
  '';

  # Wifi power save: NetworkManager leaves this at "default" (0), which defers
  # to the driver. Pin it on so ath11k actually uses PS-Poll between beacons.
  networking.networkmanager.wifi.powersave = true;

  boot.kernel.sysctl = {
    # The NMI watchdog wakes every core on a timer to detect hard lockups.
    # Useful when debugging kernel hangs, pure overhead otherwise.
    "kernel.nmi_watchdog" = 0;
    # Batch writeback into fewer, larger flushes so the NVMe gets longer
    # uninterrupted idle windows to reach its deep APST states.
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
