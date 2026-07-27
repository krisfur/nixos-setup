{ pkgs, ... }:

# General desktop applications.

{
  # binfmt registration means a chmod +x AppImage in ~/Applications just works,
  # and stays writable so Helium's zsync auto-update keeps functioning.
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;
  # Helium (Chromium) dlopens libva.so.2 for hardware video decode but doesn't
  # bundle it, and its AppRun rewrites LD_LIBRARY_PATH so env relaying is
  # unreliable. Bake libva into the sandbox instead — it finds the radeonsi
  # driver under /run/opengl-driver/lib/dri itself, no LIBVA_* needed.
  programs.appimage.package = pkgs.appimage-run.override {
    extraPkgs = pkgs: [ pkgs.libva ];
  };

  # Steam runs in an FHS env and enables 32-bit graphics libs automatically.
  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    ghostty            # terminal
    # glib checks xdg-terminal-exec before falling back to a hardcoded terminal
    # list. Ghostty is selected via ~/.config/xdg-terminals.list (home.nix).
    xdg-terminal-exec
    networkmanagerapplet # nm-applet tray + nm-connection-editor (replaces nmtui)
    iw                 # wifi diagnostics: `iw reg get`, `iw phy` channel/band list
    hyprlock           # lock screen (parallel password + fingerprint auth)
    discord            # chat
    mpv                # video
    ffmpeg             # video/audio transcoding CLI
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
}
