{ pkgs, ... }:

let
  # Session command run by greetd. Sets the bits sway and portals expect,
  # then execs the compositor.
  swaySession = pkgs.writeShellScript "sway-session" ''
    export XDG_CURRENT_DESKTOP=sway
    export XDG_SESSION_TYPE=wayland
    export NIXOS_OZONE_WL=1
    export MOZ_ENABLE_WAYLAND=1
    export QT_QPA_PLATFORM=wayland
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec ${pkgs.sway}/bin/sway
  '';
in
{
  # Recolour Papirus folders once, globally, so home-manager (useGlobalPkgs)
  # and the system list share one build. dontFixup because the colour override
  # forces a local rebuild and fixupPhase walks ~70k icon files for several
  # minutes — there are no binaries in here to strip or patch.
  nixpkgs.overlays = [
    (final: prev: {
      papirus-icon-theme =
        (prev.papirus-icon-theme.override { color = "palebrown"; })
        .overrideAttrs (_: { dontFixup = true; });
    })
  ];

  # Wayland tiling compositor.
  environment.systemPackages = with pkgs; [
    sway
    waybar
    fuzzel
    swaynotificationcenter
    swayidle
    swaybg
    grim
    slurp
    wl-clipboard
    brightnessctl
    playerctl
    pavucontrol
    polkit_gnome
    nwg-look
    libnotify
    xdg-utils
    # Theme + icons referenced by the home-manager configs.
    adw-gtk3
    # Recoloured by the overlay above.
    papirus-icon-theme
    # Thunar's Open Terminal Here / Run In Terminal shell out to a hardcoded
    # `exo-open --launch TerminalEmulator`, which in Xfce 4.20 delegates to
    # xfce4-mime-helper. programs.thunar pulls in neither, so without both the
    # menu entries fail silently. The ghostty helper they resolve to is in
    # home.nix.
    xfce.exo
    xfce.xfce4-settings
  ];

  # Login: greetd + tuigreet, launching sway.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${swaySession}";
      user = "greeter";
    };
  };

  # greetd sets services.displayManager.enable, which switches on the whole
  # graphical-desktop module, and that turns speechd on by mkDefault for screen
  # readers. Its unit runs `speech-dispatcher -t 0`, so the first Chromium app
  # that enumerates TTS voices pins the daemon plus a module process per synth
  # for the rest of the boot. No screen reader here, so drop it.
  services.speechd.enable = false;

  # Audio via PipeWire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;

    # Speaker DSP plugins for the filter-chain in home.nix. This only puts them
    # on the daemon's LV2_PATH; the graph itself is user config. lilv finds
    # plugins by LV2_PATH alone, so without this the chain fails to load.
    extraLv2Packages = [
      pkgs.lsp-plugins
      pkgs.calf
    ];
  };

  # Wayland portals: gtk default, wlr for screencast/screenshot.
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
    };
  };

  # Fingerprint reader. Enabling fprintd defaults fprintAuth to true for sudo,
  # login, greetd and hyprlock at once. The login paths are turned back off:
  # fprintd isn't reliably up that early in boot, and a greeter hanging on the
  # sensor is a bad way to lose access. Enrol per-user with `fprintd-enroll`;
  # templates live in /var/lib/fprint, so that step can't be declarative.
  services.fprintd.enable = true;
  security.pam.services.greetd.fprintAuth = false;
  security.pam.services.login.fprintAuth = false;

  # fprintd exits ~30s after going idle, pulling the device out from under a
  # running hyprlock — fingerprint then only worked if you returned within 30s.
  # Keep it resident (~5 MB).
  systemd.services.fprintd.serviceConfig.ExecStart = [
    ""
    "${pkgs.fprintd}/libexec/fprintd --no-timeout"
  ];

  # The lock screen needs its own PAM service — without one PAM falls back to
  # /etc/pam.d/other (warn + deny) and rejects every password, locking you out.
  # fprintAuth is off because hyprlock drives fprintd directly over D-Bus; a
  # pam_fprintd in the stack too makes both paths fight over the sensor.
  security.pam.services.hyprlock = {
    fprintAuth = false;
  };

  # Don't restart fprintd on resume: it tears the daemon down under a hyprlock
  # that already holds a good claim. fprintd handles suspend itself via its own
  # inhibitor. The reset happens after unlock instead (lockCmd in home.nix),
  # the only moment nothing owns the device — which this rule permits without a
  # password prompt, for fprintd.service alone.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "fprintd.service" &&
          subject.user == "kfurman") {
        return polkit.Result.YES;
      }
    });
  '';

  # polkit + keyring + dconf for gsettings-driven theming.
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  # Auto-unlock the keyring with the login password (greetd is the login PAM
  # service). Chromium/Helium store secrets here and would prompt otherwise.
  security.pam.services.greetd.enableGnomeKeyring = true;
  programs.dconf.enable = true;

  # Thunar file manager + thumbnails + trash/mounting.
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];
}
