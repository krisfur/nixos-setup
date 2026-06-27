{ pkgs, config, inputs, ... }:

let
  configDir = ../../config;
  wallpaper = "${config.xdg.configHome}/labwc/wallpaper.png";
  lockCmd = "${pkgs.swaylock-effects}/bin/swaylock -f -i ${wallpaper} --effect-blur 7x5 --config ${config.xdg.configHome}/swaylock/config";

  # labwc reads ~/.config/labwc/autostart on startup. We generate it here so
  # the helper binaries resolve to their Nix store paths.
  autostart = pkgs.writeShellScript "labwc-autostart" ''
    ${pkgs.swaybg}/bin/swaybg -i ${wallpaper} -m fill &
    ${pkgs.waybar}/bin/waybar &
    ${pkgs.swaynotificationcenter}/bin/swaync &
    ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator &
    ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &
    ${pkgs.swayidle}/bin/swayidle -w \
      timeout 300 '${lockCmd}' \
      before-sleep '${lockCmd}' &
  '';

  # Helium browser. Not in nixpkgs; it's an auto-updating AppImage. The wrapper
  # downloads the latest release into ~/Applications on first run, then execs
  # it (binfmt handles AppImage execution). Helium self-updates thereafter.
  helium = pkgs.writeShellScriptBin "helium" ''
    set -euo pipefail
    app="$HOME/Applications/helium.AppImage"
    if [ ! -x "$app" ]; then
      mkdir -p "$HOME/Applications"
      echo "Fetching latest Helium AppImage..." >&2
      url=$(${pkgs.curl}/bin/curl -fsSL \
        https://api.github.com/repos/imputnet/helium-linux/releases/latest \
        | ${pkgs.jq}/bin/jq -r '.assets[] | select(.name | test("x86_64\\.AppImage$")) | .browser_download_url')
      ${pkgs.curl}/bin/curl -fL "$url" -o "$app"
      chmod +x "$app"
    fi
    exec "$app" "$@"
  '';
in
{
  home.username = "kfurman";
  home.homeDirectory = "/home/kfurman";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  home.packages = [ helium ];

  # Desktop entry so Helium shows in fuzzel and as the default browser.
  xdg.desktopEntries.helium = {
    name = "Helium";
    genericName = "Web Browser";
    exec = "helium %U";
    icon = "applications-internet";
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
  };
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = "helium.desktop";
      "x-scheme-handler/https" = "helium.desktop";
      "text/html" = "helium.desktop";
    };
  };

  # --- GTK / icon theming (replaces the sway `exec gsettings ...` lines) ---
  gtk = {
    enable = true;
    theme = {
      name = "Nordic";
      package = pkgs.nordic;
    };
    # Keep applying Nordic to GTK4 too (the old setup themed gtk-4.0). Use
    # `null` here instead if you'd rather let libadwaita apps render natively.
    gtk4.theme = config.gtk.theme;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # --- Shell + git ---
  programs.fish.enable = true;
  programs.git = {
    enable = true;
    userName = "Krzysztof Furman";
    userEmail = "krisfur@proton.me";
    extraConfig.init.defaultBranch = "main";
  };

  # --- Vendored config files ---
  xdg.configFile = {
    # fastfetch (from macos-setup)
    "fastfetch/config.jsonc".source = "${configDir}/fastfetch/config.jsonc";
    "fastfetch/logo.png".source = "${configDir}/fastfetch/logo.png";

    # waybar (adapted for labwc: wlr modules, NixOS paths)
    "waybar/config".source = "${configDir}/waybar/config";
    "waybar/style.css".source = "${configDir}/waybar/style.css";

    # fuzzel launcher
    "fuzzel/fuzzel.ini".source = "${configDir}/fuzzel/fuzzel.ini";

    # notifications + lockscreen
    "swaync/style.css".source = "${configDir}/swaync/style.css";
    "swaylock/config".source = "${configDir}/swaylock/config";

    # labwc compositor
    "labwc/rc.xml".source = "${configDir}/labwc/rc.xml";
    "labwc/menu.xml".source = "${configDir}/labwc/menu.xml";
    "labwc/wallpaper.png".source = "${configDir}/wallpaper/wallpaper.png";
    "labwc/labwc-screenshot.sh" = {
      source = "${configDir}/labwc/labwc-screenshot.sh";
      executable = true;
    };
    "labwc/autostart".source = autostart;

    # neovim (flake input -> github.com/krisfur/neovim-config)
    "nvim/init.lua".source = "${inputs.neovim-config}/init.lua";
  };

  # Environment for the labwc session (labwc reads ~/.config/labwc/environment).
  home.file.".config/labwc/environment".text = ''
    XKB_DEFAULT_LAYOUT=gb
  '';
}
