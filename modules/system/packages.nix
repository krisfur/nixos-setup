{ pkgs, ... }:

# General desktop applications carried over from the Sway setup.
# Helium ships an auto-updating AppImage (see modules/home/home.nix); it lives
# in ~/Applications and runs via the appimage binfmt below. Dropped (Arch-only):
# gazelle-tui (-> NetworkManager applet/editor), t3code-bin, paru/AUR helpers.

{
  # Run AppImages directly (Helium). binfmt registration means a chmod +x
  # AppImage in ~/Applications "just works"; it stays writable so Helium's
  # built-in zsync auto-update keeps functioning.
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

  environment.systemPackages = with pkgs; [
    ghostty            # terminal
    networkmanagerapplet # nm-applet tray + nm-connection-editor (replaces nmtui)
    mpv                # video
    imv                # image viewer
    viu                # terminal image preview
    gimp               # image editing
    localsend          # cross-device file sharing (firewall ports opened in core.nix)
    bluetuith          # TUI bluetooth manager (waybar on-click)
    btop               # TUI system monitor (waybar on-click)
    xarchiver          # archive GUI for thunar
    gamescope          # gaming compositor
    fastfetch          # system info (config vendored via home-manager)

    # Wayland/Qt integration + MTP for phones over gvfs.
    qt6.qtwayland
    libmtp
    android-tools
  ];

  # Android device access over USB.
  services.udev.packages = [ pkgs.android-udev-rules ];
}
