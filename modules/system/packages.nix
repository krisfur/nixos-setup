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
  # Helium (Chromium) dlopens libva.so.2 for hardware video decode, but the
  # AppImage doesn't bundle it and env-var relaying into the FHS sandbox is
  # unreliable (Helium's AppRun rewrites LD_LIBRARY_PATH). Bake libva into
  # the sandbox instead; nixpkgs libva finds the radeonsi driver under
  # /run/opengl-driver/lib/dri by itself, no LIBVA_* env needed.
  programs.appimage.package = pkgs.appimage-run.override {
    extraPkgs = pkgs: [ pkgs.libva ];
  };

  # Steam runs in an FHS env and enables 32-bit graphics libs automatically.
  programs.steam.enable = true;

  environment.systemPackages = with pkgs; [
    ghostty            # terminal
    # glib only knows a hardcoded terminal list (xterm, konsole, ...) when
    # launching Terminal=true desktop entries ("Open With Neovim wrapper"),
    # but checks for xdg-terminal-exec first. Ghostty is selected via
    # ~/.config/xdg-terminals.list (home.nix).
    xdg-terminal-exec
    networkmanagerapplet # nm-applet tray + nm-connection-editor (replaces nmtui)
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
