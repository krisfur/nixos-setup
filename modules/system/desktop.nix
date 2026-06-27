{ pkgs, ... }:

let
  # Session command run by greetd. Sets the bits labwc and portals expect,
  # then execs the compositor.
  labwcSession = pkgs.writeShellScript "labwc-session" ''
    export XDG_CURRENT_DESKTOP=labwc:wlroots
    export XDG_SESSION_TYPE=wayland
    export NIXOS_OZONE_WL=1
    export MOZ_ENABLE_WAYLAND=1
    export QT_QPA_PLATFORM=wayland
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
    exec ${pkgs.labwc}/bin/labwc
  '';
in
{
  # Wayland stacking compositor.
  environment.systemPackages = with pkgs; [
    labwc
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

  # Login: greetd + tuigreet, launching labwc.
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd ${labwcSession}";
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

  # Wayland portals: gtk default, wlr for screencast/screenshot (matches the
  # old sway-portals.conf).
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

  # polkit + keyring + dconf for gsettings-driven theming.
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  programs.dconf.enable = true;

  # Thunar file manager + thumbnails + trash/mounting.
  programs.thunar.enable = true;
  programs.xfconf.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-emoji
  ];
  fonts.fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font" ];
}
