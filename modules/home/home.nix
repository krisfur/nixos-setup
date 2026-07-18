{ pkgs, config, lib, inputs, ... }:

let
  configDir = ../../config;
  wallpaper = "${config.xdg.configHome}/labwc/wallpaper.png";
  lockCmd = "${pkgs.swaylock-effects}/bin/swaylock -f -i ${wallpaper} --effect-blur 7x5 --config ${config.xdg.configHome}/swaylock/config";

  # Controller input never reaches the compositor's seat, so swayidle counts a
  # gamepad session as idle and locks mid-game. Steam wraps every game launch
  # (native and Proton) in a "reaper SteamLaunch AppId=..." process that lives
  # for exactly the game's lifetime, so skip the idle lock while one exists.
  # Note: after the game exits the timer only re-arms on the next input event.
  idleLockCmd = pkgs.writeShellScript "idle-lock" ''
    ${pkgs.procps}/bin/pgrep -f 'SteamLaunch AppId=' >/dev/null && exit 0
    exec ${lockCmd}
  '';

  # Suspend after an hour idle (same suspend as closing the lid), with the
  # same skip-while-gaming guard as the lock. Media playback holds the
  # Wayland idle inhibitor, which already blocks all swayidle timeouts.
  idleSuspendCmd = pkgs.writeShellScript "idle-suspend" ''
    ${pkgs.procps}/bin/pgrep -f 'SteamLaunch AppId=' >/dev/null && exit 0
    exec ${pkgs.systemd}/bin/systemctl suspend
  '';

  # labwc reads ~/.config/labwc/autostart on startup. We generate it here so
  # the helper binaries resolve to their Nix store paths.
  autostart = pkgs.writeShellScript "labwc-autostart" ''
    # pam_gnome_keyring unlocks a keyring daemon at login, but D-Bus sometimes
    # activates a second, *locked* secrets daemon before the unlocked one claims
    # the bus name - the intermittent keyring prompt after a rebuild+reboot.
    # Re-run --start here, inside the session, to adopt the already-unlocked
    # daemon and make it own org.freedesktop.secrets on the session bus before
    # any app (Helium) asks, pre-empting the locked instance. Run synchronously
    # so the name is claimed before the apps below launch.
    eval "$(${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets,ssh,pkcs11)"
    export SSH_AUTH_SOCK
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      SSH_AUTH_SOCK GNOME_KEYRING_CONTROL DISPLAY WAYLAND_DISPLAY 2>/dev/null || true

    # Tell systemd a graphical session is up so user units wanted by
    # graphical-session.target (easyeffects) start. That target refuses
    # manual starts, so go through labwc-session.target, which BindsTo it.
    # Must run after the env push above so those units see WAYLAND_DISPLAY.
    ${pkgs.systemd}/bin/systemctl --user start labwc-session.target

    ${pkgs.swaybg}/bin/swaybg -i ${wallpaper} -m fill &
    ${pkgs.waybar}/bin/waybar &
    ${pkgs.swaynotificationcenter}/bin/swaync &
    ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator &
    ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &
    ${pkgs.swayidle}/bin/swayidle -w \
      timeout 900 '${idleLockCmd}' \
      timeout 3600 '${idleSuspendCmd}' \
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

  # Ghostty single-instance mode segfaults when closing one of several windows
  # sharing the process, killing them all (ghostty-org/ghostty#5868). Force it
  # off at every launch point: this override (shadows the stock desktop entry,
  # keeping its X-TerminalArg* keys for xdg-terminal-exec below), labwc
  # rc.xml/menu.xml, waybar on-clicks, and fuzzel.ini.
  xdg.desktopEntries."com.mitchellh.ghostty" = {
    name = "Ghostty";
    genericName = "Terminal Emulator";
    exec = "ghostty --gtk-single-instance=false";
    icon = "com.mitchellh.ghostty";
    categories = [ "System" "TerminalEmulator" ];
    terminal = false;
    settings = {
      X-TerminalArgExec = "-e";
      X-TerminalArgTitle = "--title=";
      X-TerminalArgAppId = "--class=";
      X-TerminalArgDir = "--working-directory=";
      X-TerminalArgHold = "--wait-after-command";
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

  # Speaker DSP: the P14s speakers are tuned for Windows' Dolby driver and
  # sound tinny without it. EasyEffects runs as a background service and
  # applies a community ThinkPad EQ preset (bass enhancer + multiband
  # compressor). Its output is pinned to the internal speaker sink (see the
  # activation script below), so headphones, DACs, and any other output play
  # untouched — no per-device presets needed.
  services.easyeffects = {
    enable = true;
    preset = "thinkpad-unsuck";
  };

  # Session marker started by labwc's autostart (see above). labwc itself
  # never activates graphical-session.target, and that target refuses manual
  # starts — the supported pattern is a session-scoped target bound to it.
  systemd.user.targets.labwc-session = {
    Unit = {
      Description = "labwc compositor session";
      BindsTo = [ "graphical-session.target" ];
    };
  };

  # EasyEffects 8 stores settings in a KConfig file it rewrites at runtime, so
  # the speaker pin can't be a read-only store symlink like the configs below.
  # Instead, enforce the two [StreamOutputs] keys on every activation:
  # useDefaultOutputDevice=false stops EasyEffects from following the default
  # sink, and outputDevice fixes it to the internal speakers.
  home.activation.easyeffectsPinSpeakers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.xdg.configHome}/easyeffects/db/easyeffectsrc" <<'EOF'
    import configparser, os, sys
    path = sys.argv[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cp = configparser.ConfigParser()
    cp.optionxform = str
    cp.read(path)
    if "StreamOutputs" not in cp:
        cp["StreamOutputs"] = {}
    cp["StreamOutputs"]["useDefaultOutputDevice"] = "false"
    cp["StreamOutputs"]["outputDevice"] = "alsa_output.pci-0000_c4_00.6.HiFi__Speaker__sink"
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
    EOF
  '';

  # Modern cursor (the default is the chunky X11 fallback). Also exported to
  # the labwc environment below so the compositor itself uses it.
  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # --- Shell + git ---
  programs.fish = {
    enable = true;
    # Greet each new interactive shell (terminal window/tab) with fastfetch.
    interactiveShellInit = "fastfetch";
  };
  programs.git = {
    enable = true;
    settings = {
      user.name = "Krzysztof Furman";
      user.email = "krisfur@proton.me";
      init.defaultBranch = "main";
      # Use the gh CLI's token for HTTPS GitHub git operations (push/pull),
      # the declarative equivalent of `gh auth setup-git`. Scoped to GitHub so
      # gh isn't invoked for other remotes. Requires a successful `gh auth login`.
      credential = {
        "https://github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
        "https://gist.github.com".helper = "!${pkgs.gh}/bin/gh auth git-credential";
      };
    };
  };

  # --- Vendored config files ---
  xdg.configFile = {
    # fastfetch (from macos-setup)
    "fastfetch/config.jsonc".source = "${configDir}/fastfetch/config.jsonc";
    "fastfetch/logo.png".source = "${configDir}/fastfetch/logo.png";

    # waybar (adapted for labwc: wlr modules, NixOS paths)
    "waybar/config".source = "${configDir}/waybar/config";
    "waybar/style.css".source = "${configDir}/waybar/style.css";

    # ghostty terminal (default window size bumped so btop fits)
    "ghostty/config".source = "${configDir}/ghostty/config";

    # fuzzel launcher
    "fuzzel/fuzzel.ini".source = "${configDir}/fuzzel/fuzzel.ini";

    # notifications + lockscreen
    "swaync/style.css".source = "${configDir}/swaync/style.css";
    "swaylock/config".source = "${configDir}/swaylock/config";

    # xdg-terminal-exec (packages.nix): glib consults it to launch
    # Terminal=true desktop entries (e.g. "Open With Neovim wrapper");
    # this picks ghostty as that terminal.
    "xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

    # labwc compositor
    "labwc/rc.xml".source = "${configDir}/labwc/rc.xml";
    "labwc/menu.xml".source = "${configDir}/labwc/menu.xml";
    "labwc/themerc-override".source = "${configDir}/labwc/themerc-override";
    "labwc/wallpaper.png".source = "${configDir}/wallpaper/wallpaper.png";
    "labwc/labwc-screenshot.sh" = {
      source = "${configDir}/labwc/labwc-screenshot.sh";
      executable = true;
    };
    "labwc/autostart".source = autostart;

    # neovim (flake input -> github.com/krisfur/neovim-config)
    "nvim/init.lua".source = "${inputs.neovim-config}/init.lua";

    # (No touchpad swipe-to-switch-desktop: labwc's libinput 3-finger-drag
    # grabs the focused window on a fast 3-finger swipe and threeFingerDrag=no
    # isn't honored to disable it, so the window rode along to the new desktop.
    # Desktops are switched with the keyboard instead - Ctrl+Alt+Left/Right.)
  };

  # EasyEffects output preset (from sebastian-de/easyeffects-thinkpad-unsuck).
  # EasyEffects 8 reads user presets from XDG data, not XDG config — it
  # actively migrates (moves) anything found under ~/.config/easyeffects to
  # ~/.local/share/easyeffects at startup, so the link must live here or EE
  # will fight home-manager over it.
  xdg.dataFile."easyeffects/output/thinkpad-unsuck.json".source =
    "${configDir}/easyeffects/thinkpad-unsuck.json";

  # Environment for the labwc session (labwc reads ~/.config/labwc/environment).
  home.file.".config/labwc/environment".text = ''
    XKB_DEFAULT_LAYOUT=gb
    XCURSOR_THEME=Bibata-Modern-Ice
    XCURSOR_SIZE=24
  '';
}
