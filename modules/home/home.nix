{ pkgs, config, lib, inputs, ... }:

let
  configDir = ../../config;
  wallpaper = "${config.xdg.configHome}/sway/wallpaper.jpg";
  # hyprlock, not swaylock: it waits on password and fingerprint concurrently,
  # which swaylock can't (it collects input first, then runs PAM).
  hyprlockBin = "${pkgs.hyprlock}/bin/hyprlock --grace 0 --no-fade-in";

  # Unguarded on purpose: an orphaned hyprlock would otherwise no-op every lock
  # path. The restart clears a stale fprintd claim that blocks later locks; only
  # safe after hyprlock exits. Needs the polkit rule in desktop.nix.
  # Don't try to force a redraw with SIGUSR2: hyprlock installs that handler
  # some way into startup, and until then the default disposition terminates
  # the process — the locker dies on launch and the machine sits unlocked.
  lockCmd = pkgs.writeShellScript "lock" ''
    ${hyprlockBin}
    ${pkgs.systemd}/bin/systemctl restart fprintd.service || true
  '';

  # swayidle waits for before-sleep to exit and hyprlock has no daemonize flag,
  # so background it and settle before the machine goes down. Guarded here only:
  # this is the one path that can fire on top of an existing lock.
  sleepLockCmd = pkgs.writeShellScript "sleep-lock" ''
    ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && exit 0
    ${lockCmd} &
    sleep 1
  '';

  # Controller input never reaches the seat, so swayidle counts a gamepad
  # session as idle and locks mid-game; Steam's reaper process marks a running
  # game. Backgrounded because swayidle -w waits, and a foreground hyprlock
  # would block the 1800s suspend timeout below from ever firing.
  idleLockCmd = pkgs.writeShellScript "idle-lock" ''
    ${pkgs.procps}/bin/pgrep -f 'SteamLaunch AppId=' >/dev/null && exit 0
    ${lockCmd} &
  '';

  # Suspend after 30 min idle, with the same skip-while-gaming guard. Media
  # playback holds the Wayland idle inhibitor, which blocks swayidle already.
  idleSuspendCmd = pkgs.writeShellScript "idle-suspend" ''
    ${pkgs.procps}/bin/pgrep -f 'SteamLaunch AppId=' >/dev/null && exit 0
    exec ${pkgs.systemd}/bin/systemctl suspend
  '';

  # sway execs ~/.config/sway/autostart (see the `exec` line in the sway config).
  # We generate it here so the helper binaries resolve to their Nix store paths.
  autostart = pkgs.writeShellScript "sway-autostart" ''
    # D-Bus sometimes activates a second, *locked* secrets daemon before the
    # one pam_gnome_keyring unlocked claims the bus name — the intermittent
    # keyring prompt after a rebuild+reboot. Re-run --start synchronously to
    # adopt the unlocked daemon and claim org.freedesktop.secrets first.
    eval "$(${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets,ssh,pkcs11)"
    export SSH_AUTH_SOCK
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      SSH_AUTH_SOCK GNOME_KEYRING_CONTROL DISPLAY WAYLAND_DISPLAY 2>/dev/null || true

    # Starts user units wanted by graphical-session.target (easyeffects). That
    # target refuses manual starts, hence sway-session.target which BindsTo it.
    # Must run after the env push so those units see WAYLAND_DISPLAY.
    ${pkgs.systemd}/bin/systemctl --user start sway-session.target

    ${pkgs.swaybg}/bin/swaybg -i ${wallpaper} -m fill &
    ${pkgs.waybar}/bin/waybar &
    # swaync is deliberately absent: its own user unit is started by the
    # systemctl line above, and a second launch loses the bus-name race.
    ${pkgs.networkmanagerapplet}/bin/nm-applet --indicator &
    ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &
    ${pkgs.swayidle}/bin/swayidle -w \
      timeout 900 '${idleLockCmd}' \
      timeout 1800 '${idleSuspendCmd}' \
      before-sleep '${sleepLockCmd}' &
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
    # Hardware video decode (VA-API): Chromium disables it on Linux, costing
    # ~3-5 W software-decoding VP9/AV1. The flag was renamed around Chromium
    # 131, so pass both names — unknown ones are ignored. libva is baked into
    # the appimage-run sandbox (packages.nix); env vars don't survive AppRun.
    # Verify in about:gpu → "Video Acceleration Information": empty means CPU
    # decode, regardless of what the feature list above it claims.
    exec "$app" \
      --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
      "$@"
  '';

  # Claude Code. Not from nixpkgs: the read-only store breaks its self-updater
  # and pnpm's global prefix hits EROFS. This wrapper runs Anthropic's official
  # installer on first launch, dropping a self-updating native ELF into
  # ~/.local/bin so `claude update` works. Dynamically linked — nix-ld (dev.nix)
  # provides its loader. PATH is pinned rather than assumed.
  claude = pkgs.writeShellScriptBin "claude" ''
    set -euo pipefail
    bin="$HOME/.local/bin/claude"
    if [ ! -x "$bin" ]; then
      echo "Fetching latest Claude Code (native, self-updating)..." >&2
      export PATH="${lib.makeBinPath [ pkgs.curl pkgs.coreutils pkgs.jq pkgs.gnused pkgs.gnugrep pkgs.bash ]}:$PATH"
      curl -fsSL https://claude.ai/install.sh | bash
    fi
    exec "$bin" "$@"
  '';
in
{
  home.username = "kfurman";
  home.homeDirectory = "/home/kfurman";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  home.packages = [ helium claude ];

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

  # Shadows the stock desktop entry, keeping its X-TerminalArg* keys. The
  # single-instance setting lives in config/ghostty/config, not on the exec
  # line, so every launch path agrees.
  xdg.desktopEntries."com.mitchellh.ghostty" = {
    name = "Ghostty";
    genericName = "Terminal Emulator";
    exec = "ghostty";
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
    # nordic was dropped from nixpkgs (it needed gtk-engine-murrine, a GTK2
    # engine, which went unmaintained). adw-gtk3 gives GTK3 apps the libadwaita
    # look; GTK4 apps get it natively, hence gtk4.theme = null. The warm accent
    # comes from the dconf accent-color below rather than a theme variant.
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk4.theme = null;

    # Plain GTK4 apps (pavucontrol) don't follow the dconf color-scheme — that's
    # libadwaita behaviour — so they come up light without this.
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;

    # GTK3 has no accent-color setting, so adw-gtk3's blue selection shows
    # through on GTK3 menus (nm-applet). Override the named colours instead.
    gtk3.extraCss = ''
      @define-color theme_selected_bg_color #c9a06b;
      @define-color theme_selected_fg_color #1e1a16;
      @define-color accent_bg_color #c9a06b;
      @define-color accent_fg_color #1e1a16;
      @define-color accent_color #c9a06b;

      /* adw-gtk3's menu greys are neutral, which reads cold next to the warm
         palette everywhere else. Restyle directly — the @define-colors above
         don't reach menu backgrounds. */
      menu, .menu, .context-menu, popover, popover.background,
      popover > contents, .csd popup decoration {
        background-color: #2b2520;
        color: #ddd0ba;
        border: 1px solid #574c40;
      }
      menu menuitem:hover, .menu menuitem:hover,
      popover listview row:selected, popover modelbutton:hover {
        background-color: #c9a06b;
        color: #1e1a16;
      }
    '';

    # Focus rings, scoped to real controls. A bare `:focus-visible` also matches
    # ghostty's terminal widget, which fills the window — that drew a ring in
    # the same colour as the sway border just inside it, so the window looked
    # like it randomly grew a thicker border while typing.
    gtk4.extraCss = ''
      button:focus-visible,
      entry:focus-visible,
      spinbutton:focus-visible,
      checkbutton:focus-visible,
      radiobutton:focus-visible,
      switch:focus-visible,
      combobox:focus-visible,
      dropdown:focus-visible,
      tab:focus-visible,
      row:focus-visible {
        outline-color: #c9a06b;
        outline-style: solid;
        outline-width: 2px;
        outline-offset: -2px;
      }

      /* Dialog action buttons (libadwaita puts them in .response-area) sit on a
         busy background, so add an inner ring to make the selection obvious. */
      .response-area button:focus-visible,
      .dialog-action-area button:focus-visible,
      dialog button:focus-visible {
        box-shadow: inset 0 0 0 2px rgba(201, 160, 107, 0.5);
      }

      /* ghostty's OSC 9;4 progress bar takes libadwaita's accent, which stays
         blue regardless of the accent-color key below. Set it directly. */
      progressbar > trough > progress {
        background-color: #c9a06b;
      }
    '';

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    accent-color = "orange";
  };

  # Thunar is GTK3 and falls back to gtk-3.0/settings.ini while the xsettings
  # channel is unset, but pin it so an xfconf write can't silently override.
  xfconf.settings.xsettings = {
    "Net/ThemeName" = "adw-gtk3-dark";
    "Net/IconThemeName" = "Papirus-Dark";
    "Gtk/CursorThemeName" = "Bibata-Modern-Classic";
  };

  # EasyEffects 8 is Qt6, not GTK, so it defaults to Breeze and ignores every
  # GTK setting above. Point Qt's platform theme at GTK to pull the same colours.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
  };

  # Speaker DSP: the P14s speakers are tuned for Windows' Dolby driver and
  # sound tinny without it, so apply a community ThinkPad EQ preset. Pinned to
  # the internal speaker sink below, so headphones and DACs play untouched.
  services.easyeffects = {
    enable = true;
    preset = "thinkpad-unsuck";
  };

  # EasyEffects ignores --load-preset on its own service start (handled before
  # the pipeline is ready), leaving an empty chain. Re-issue over IPC once it's
  # up and verify via PipeWire: ee_soe_* nodes exist only when the chain is
  # actually populated.
  systemd.user.services.easyeffects.Service.ExecStartPost =
    "${pkgs.writeShellScript "easyeffects-load-preset" ''
      sleep 2
      for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
        ${pkgs.easyeffects}/bin/easyeffects -l thinkpad-unsuck >/dev/null 2>&1
        ${pkgs.pipewire}/bin/pw-dump 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q ee_soe_bass_enhancer && exit 0
        sleep 1
      done
      echo "easyeffects: preset thinkpad-unsuck failed to load" >&2
      exit 1
    ''}";

  # sway never activates graphical-session.target and that target refuses
  # manual starts, so bind a session-scoped one to it (started by autostart).
  systemd.user.targets.sway-session = {
    Unit = {
      Description = "sway compositor session";
      BindsTo = [ "graphical-session.target" ];
    };
  };

  # EasyEffects 8 rewrites its KConfig at runtime, so the speaker pin can't be
  # a read-only store symlink. Enforce the two keys on every activation:
  # useDefaultOutputDevice=false stops it following the default sink.
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

  # EasyEffects picks a KDE colour scheme by name, defaulting to BreezeDark,
  # and that overrides the Qt platform theme. Note this is ~/.config/easyeffectsrc,
  # a different file from the db/ one above. Dust.colors is the palette below.
  home.activation.easyeffectsColorScheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.xdg.configHome}/easyeffectsrc" <<'EOF'
    import configparser, os, sys
    path = sys.argv[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cp = configparser.ConfigParser()
    cp.optionxform = str
    cp.read(path)
    if "UiSettings" not in cp:
        cp["UiSettings"] = {}
    cp["UiSettings"]["ColorScheme"] = "Dust"
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
    EOF
  '';

  # Claude Code's own themes hardcode colours; "dark-ansi" makes it use the
  # terminal's ANSI palette instead, so it follows ghostty. Merged rather than
  # symlinked because claude rewrites this file when settings change.
  home.activation.claudeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}/.claude/settings.json" <<'EOF'
    import json, os, sys
    path = sys.argv[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path) as f:
            cfg = json.load(f)
    except Exception:
        cfg = {}
    cfg["theme"] = "dark-ansi"
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    EOF
  '';

  # Modern cursor (the default is the chunky X11 fallback). sway also picks it
  # up via `seat seat0 xcursor_theme Bibata-Modern-Classic` in config/sway/config.
  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    name = "Bibata-Modern-Classic";
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
      # Declarative `gh auth setup-git`. Scoped to GitHub so gh isn't invoked
      # for other remotes. Requires a successful `gh auth login`.
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

    # waybar (wlr modules, NixOS paths)
    "waybar/config".source = "${configDir}/waybar/config";
    "waybar/style.css".source = "${configDir}/waybar/style.css";

    # ghostty terminal (default window size bumped so btop fits)
    "ghostty/config".source = "${configDir}/ghostty/config";

    # fuzzel launcher
    "fuzzel/fuzzel.ini".source = "${configDir}/fuzzel/fuzzel.ini";

    # notifications
    "swaync/style.css".source = "${configDir}/swaync/style.css";

    # Lock screen. Generated, not vendored, so the wallpaper path resolves.
    # Colours mirror the waybar pills in config/waybar/style.css.
    "hypr/hyprlock.conf".text = ''
      background {
          monitor =
          path = ${wallpaper}
          blur_passes = 3
          blur_size = 7
      }

      label {
          monitor =
          # Polled far faster than a clock needs: this timer is the only thing
          # repainting the input field, which re-evaluates its placeholder only
          # on redraw, so it sets how fast the fingerprint icon appears.
          text = cmd[update:500] date +"%H:%M"
          color = rgb(f2e8d5)
          font_size = 72
          font_family = JetBrainsMono Nerd Font
          position = 0, 150
          halign = center
          valign = center
      }

      label {
          monitor =
          text = cmd[update:30000] date +"%A, %e %B"
          color = rgb(ddd0ba)
          font_size = 16
          font_family = JetBrainsMono Nerd Font
          position = 0, 80
          halign = center
          valign = center
      }

      input-field {
          monitor =
          size = 200, 50
          rounding = 12
          outline_thickness = 1
          inner_color = rgb(2b2520)
          outer_color = rgb(574c40)
          check_color = rgb(c9a06b)
          fail_color = rgb(b0574a)
          font_color = rgb(f2e8d5)
          font_family = JetBrainsMono Nerd Font
          dots_size = 0.25
          dots_spacing = 0.3
          dots_rounding = -1
          # Static, not $FPRINTPROMPT: that variable also carries hyprlock's
          # retry prose, which rendered at 24pt and shoved the layout around
          # after any failed scan.
          placeholder_text = <span size="24pt"> 󰌾 <span alpha="60%">/</span> 󰈷 </span>
          fail_text = <i>$FAIL</i>
          fade_on_empty = false
      }

      auth {
          fingerprint {
              enabled = true
              # Wiki-undocumented (hyprlock#625). The 250ms default burns every
              # retry before the reader is back from a long suspend.
              retry_delay = 2000
          }
      }
    '';

    # Picks ghostty as the terminal for Terminal=true desktop entries, via
    # xdg-terminal-exec (packages.nix).
    "xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

    # sway compositor
    "sway/config".source = "${configDir}/sway/config";
    "sway/wallpaper.jpg".source = "${configDir}/wallpaper/wallpaper.jpg";
    # $lockcmd and the lid bindswitch point here so they get the same guards.
    "sway/lock.sh" = {
      source = lockCmd;
      executable = true;
    };

    "sway/sway-screenshot.sh" = {
      source = "${configDir}/sway/sway-screenshot.sh";
      executable = true;
    };
    "sway/cycle-workspace.sh" = {
      source = "${configDir}/sway/cycle-workspace.sh";
      executable = true;
    };
    "sway/autostart".source = autostart;

    # neovim (flake input -> github.com/krisfur/neovim-config)
    "nvim/init.lua".source = "${inputs.neovim-config}/init.lua";
  };

  # Preset from sebastian-de/easyeffects-thinkpad-unsuck. Must live in XDG
  # data, not config: EasyEffects 8 moves anything under ~/.config/easyeffects
  # to ~/.local/share/easyeffects at startup and would fight home-manager.
  xdg.dataFile."easyeffects/output/thinkpad-unsuck.json".source =
    "${configDir}/easyeffects/thinkpad-unsuck.json";

  # KDE colour scheme in the Dust palette, for Qt apps that pick a scheme by
  # name rather than following the platform theme (EasyEffects).
  xdg.dataFile."color-schemes/Dust.colors".source =
    "${configDir}/color-schemes/Dust.colors";
}
