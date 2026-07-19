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

  # ppd 0.30 ships optional amdgpu actions whose on/off state lives in
  # /var/lib/power-profiles-daemon, not in config. Pin both here instead:
  # block amdgpu_panel_power (ABM) from loading at all — it visibly dims the
  # panel on power-saver, which is this machine's default unplugged state —
  # and re-assert amdgpu_dpm (GPU clock tuning, no visual effect) on every
  # daemon start so the stateful toggle can never drift. The leading "" in
  # ExecStart clears the upstream unit's entry before replacing it.
  systemd.services.power-profiles-daemon.serviceConfig = {
    ExecStart = [
      ""
      "${pkgs.power-profiles-daemon}/libexec/power-profiles-daemon --block-action amdgpu_panel_power"
    ];
    ExecStartPost = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl configure-action --enable amdgpu_dpm";
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
  '';

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
