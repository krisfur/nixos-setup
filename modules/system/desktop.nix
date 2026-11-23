{ pkgs, ... }:

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

  # Desktop utilities alongside Plasma.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    libnotify
    xdg-utils
    # Theme + icons referenced by the home-manager configs.
    adw-gtk3
    # Recoloured by the overlay above.
    papirus-icon-theme
  ];

  # KDE Plasma. User settings in modules/home/plasma.nix.
  services.desktopManager.plasma6.enable = true;
  # Plasma turns on the KDE PIM stack (Akonadi, KMail, Kontact, Merkuro and its
  # contacts tray widget) by default; none of it is used here.
  programs.kde-pim.enable = false;
  # Ghostty is the terminal and nothing serves remote desktops or reads KDE's
  # handbook here. Elisa stays: it plays a folder of music better than mpv.
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    khelpcenter
    krdp
  ];

  # Login: greetd + tuigreet, launching Plasma (same command as its session file).
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd '${pkgs.kdePackages.plasma-workspace}/libexec/plasma-dbus-run-session-if-needed ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland'";
      user = "greeter";
    };
  };

  # greetd sets services.displayManager.enable, which switches on the whole
  # graphical-desktop module, and that turns speechd on by mkDefault for screen
  # readers. Its unit runs `speech-dispatcher -t 0`, so the first Chromium app
  # that enumerates TTS voices pins the daemon plus a module process per synth
  # for the rest of the boot. No screen reader here, so drop it.
  services.speechd.enable = false;
  # Plasma enables the Orca screen reader by default, which forces speechd on.
  services.orca.enable = false;

  # Audio via PipeWire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    # No jack.enable: deprecated (global LD_LIBRARY_PATH) and nothing here uses
    # JACK. Run a JACK app through `pw-jack` from pipewire.jack if one appears.

    # Speaker DSP plugins for the filter-chain in home.nix. This only puts them
    # on the daemon's LV2_PATH; the graph itself is user config. lilv finds
    # plugins by LV2_PATH alone, so without this the chain fails to load.
    extraLv2Packages = [
      pkgs.lsp-plugins
      pkgs.calf
    ];
  };

  # Fingerprint reader. Enabling fprintd defaults fprintAuth to true for sudo,
  # login and greetd at once. The login paths are turned back off:
  # fprintd isn't reliably up that early in boot, and a greeter hanging on the
  # sensor is a bad way to lose access. Enrol per-user with `fprintd-enroll`;
  # templates live in /var/lib/fprint, so that step can't be declarative.
  services.fprintd.enable = true;
  security.pam.services.greetd.fprintAuth = false;
  security.pam.services.login.fprintAuth = false;

  # fprintd exits ~30s after going idle, pulling the device out from under a
  # running lock screen (seen with hyprlock under sway): fingerprint then only
  # worked if you returned within 30s. Keep it resident (~5 MB).
  systemd.services.fprintd.serviceConfig.ExecStart = [
    ""
    "${pkgs.fprintd}/libexec/fprintd --no-timeout"
  ];

  # polkit + dconf for gsettings-driven GTK theming.
  security.polkit.enable = true;
  programs.dconf.enable = true;

  # KWallet unlocks with the login password via pam_kwallet5, which Plasma adds
  # to the `login` PAM service; greetd's stack includes `login`. Needs the
  # wallet to be "kdewallet" with the login password.

  # Trash, mounting and MTP for GTK apps (Dolphin uses KIO instead).
  services.gvfs.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];

  # icon-theme.cache for the system profile's themes. Plasma brings uncached
  # breeze/hicolor, which Papirus inherits; GTK otherwise scans them per launch.
  gtk.iconCache.enable = true;
}
