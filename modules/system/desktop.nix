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
  # Wayland tiling compositor.
  environment.systemPackages = with pkgs; [
    sway
    waybar
    fuzzel
    swaynotificationcenter
    swaylock-effects
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
    nordic
    papirus-icon-theme
  ];

  # Login: greetd + tuigreet, launching sway.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd ${swaySession}";
      user = "greeter";
    };
  };

  # Audio via PipeWire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
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

  # swaylock authenticates via a PAM service of the same name. Without this
  # stack PAM denies by default and the lock screen becomes unbreakable.
  security.pam.services.swaylock = { };

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
