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

  # Networking.
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # localsend (from the old Sway setup's ufw rules).
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [
    53317
    3658 # RPCS3 / RPCN peer-to-peer netplay.
  ];

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

  # The NixOS default (WARN) hides scans, DHCP, and whether an activation was
  # automatic or user-requested, which left the 6 GHz reconnect issue opaque.
  networking.networkmanager.logLevel = "INFO";

  # Prefer 6 GHz wherever it exists as its own SSID.
  #
  # NM has no band preference to set: 802-11-wireless.band only takes "a"/"bg"
  # (no 6 GHz value) and locks a profile to one band rather than ranking them,
  # and NetworkManager.conf has no global equivalent. When an AP puts 6 GHz on
  # a separate SSID, preferring the band means preferring that profile, so the
  # rule here is: any saved profile currently on air above 5900 MHz gets
  # autoconnect-priority 10, which outranks everything left at the default 0.
  # No SSID is named, so this follows to any network. It only ever raises a
  # priority, never lowers one, so a hand-set value is never stomped.
  #
  # It also runs on resume because ath11k re-inits its firmware there and the
  # 6 GHz half of the channel list only returns with the regulatory push
  # ("Channel list changed: 6 GHz was enabled"). ath11k holds that update until
  # any running scan ends (reg.c), and NM's first post-resume scan starts about
  # 0.1s after the push arrives, so 6 GHz usually returns only when a ~4s scan
  # of all 62 channels completes, and NM's next scan may race it and lose too.
  # Measured over 150 resumes: connects land about one scan after the band
  # returns, at 4s, 8s, 13s, or later. So abort that first scan to let the update
  # through, then probe saved hidden networks on the 6 GHz PSC channels only,
  # which is far shorter than a full scan. If that misses, NM's scans still run.
  systemd.services.wifi-prefer-6ghz = {
    description = "Rank saved wifi profiles seen on 6 GHz above the rest";
    after = [ "NetworkManager.service" "suspend.target" ];
    wantedBy = [ "multi-user.target" "suspend.target" ];
    path = with pkgs; [ networkmanager iw gawk gnugrep coreutils ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "90s";
    };
    script = ''
      seen=$(mktemp)
      trap 'rm -f "$seen"' EXIT

      dev=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2 == "wifi" { print $1; exit }')
      disconnected() { nmcli -g GENERAL.STATE device show "$dev" 2>/dev/null | grep -q '^30 '; }

      if [ -n "$dev" ]; then
        for i in $(seq 30); do
          if disconnected; then break; fi
          sleep 0.1
        done

        probe=()
        while read -r uuid; do
          if [ "$(nmcli -g 802-11-wireless.hidden connection show "$uuid")" = yes ]; then
            probe+=(ssid "$(nmcli -e no -g 802-11-wireless.ssid connection show "$uuid")")
          fi
        done < <(nmcli -t -f UUID,TYPE connection show | awk -F: '$2 == "802-11-wireless" { print $1 }')

        # 5975 + 80n MHz are the PSC channels.
        psc=$(iw phy | awk '/\* 6[0-9]+\.0 MHz/ && !/disabled/ { f = $2 + 0; if ((f - 5975) % 80 == 0) print f }')

        if disconnected; then
          for i in $(seq 30); do
            if iw dev "$dev" scan abort >/dev/null 2>&1; then break; fi
            sleep 0.1
          done
          if [ ''${#probe[@]} -gt 0 ] && [ -n "$psc" ]; then
            for i in 1 2 3 4; do
              sleep 0.3
              disconnected || break
              # shellcheck disable=SC2086
              iw dev "$dev" scan trigger freq $psc "''${probe[@]}" >/dev/null 2>&1 || true
              sleep 0.5
            done
          fi
        fi
      fi

      # Retry: on resume the first scans run before the band is back.
      for i in 1 2 3 4 5 6; do
        if nmcli device wifi rescan >/dev/null 2>&1; then
          sleep 3
          # FREQ first so the frequency is the field that cannot contain a
          # colon; nmcli escapes colons inside the SSID, hence the gsub.
          nmcli -t -f FREQ,SSID device wifi list \
            | awk -F: '$1 + 0 > 5900 { sub(/^[^:]*:/, ""); gsub(/\\:/, ":"); if (length($0)) print }' \
            | sort -u > "$seen"
          if [ -s "$seen" ]; then break; fi
        fi
        sleep 5
      done

      nmcli -t -f UUID,TYPE connection show \
        | awk -F: '$2 == "802-11-wireless" { print $1 }' \
        | while read -r uuid; do
            ssid=$(nmcli -g 802-11-wireless.ssid connection show "$uuid") || continue
            grep -qxF "$ssid" "$seen" || continue
            prio=$(nmcli -g connection.autoconnect-priority connection show "$uuid")
            if [ "$prio" -lt 10 ] 2>/dev/null; then
              nmcli connection modify "$uuid" connection.autoconnect-priority 10
            fi
          done
    '';
  };

  # Mark any profile that comes up on 6 GHz as hidden so NM probes for it by
  # name. Passive scans keep missing the 6 GHz BSS (6 scans over 50s at boot on
  # 2026-10-31) while a directed probe finds it at once, which is why the
  # applet's "hidden network" connect always worked. Cost: the SSID goes out in
  # probe requests wherever the laptop scans. Only ever sets yes, never clears.
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "wifi-6ghz-hidden" ''
        [ "$2" = up ] && [ -n "$CONNECTION_UUID" ] || exit 0
        nmcli=${pkgs.networkmanager}/bin/nmcli
        [ "$($nmcli -g connection.type connection show "$CONNECTION_UUID")" = 802-11-wireless ] || exit 0
        freq=$($nmcli -t -f IN-USE,FREQ device wifi list ifname "$1" --rescan no \
          | ${pkgs.gawk}/bin/awk -F: '$1 == "*" { print $2 + 0 }')
        [ "''${freq:-0}" -gt 5900 ] || exit 0
        [ "$($nmcli -g 802-11-wireless.hidden connection show "$CONNECTION_UUID")" = yes ] \
          || $nmcli connection modify "$CONNECTION_UUID" 802-11-wireless.hidden yes
      '';
    }
  ];

  # 16 GB minus the 4 GB UMA carve-out leaves ~11.8 GB, and games that want 16 GB
  # then have nothing to reclaim but page cache — including their own mapped
  # pages, which thrashes back off the NVMe. zstd zram gives the anon pages
  # somewhere to go at roughly 3:1.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  boot.kernel.sysctl = {
    # Per-core lockup-detector timer; only useful when debugging kernel hangs.
    "kernel.nmi_watchdog" = 0;
    # Fewer, larger writeback flushes so the NVMe reaches deep APST states.
    "vm.dirty_writeback_centisecs" = 1500;
    # ...but bound how much can pile up between them. The ratio defaults are
    # 10/20% of RAM, so a 15s interval let >1 GB accumulate and the flush stalled
    # everything behind it — heard as periodic audio dropouts under load.
    "vm.dirty_background_bytes" = 64 * 1024 * 1024;
    "vm.dirty_bytes" = 256 * 1024 * 1024;
    # zram is RAM: swapping to it beats evicting page cache, and it has no seek
    # cost so the default 8-page readahead is wasted work.
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
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
