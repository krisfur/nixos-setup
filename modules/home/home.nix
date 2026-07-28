{ pkgs, config, lib, inputs, ... }:

let
  configDir = ../../config;
  wallpaper = "${config.xdg.configHome}/sway/wallpaper.png";
  # hyprlock, not swaylock: it waits on password and fingerprint concurrently,
  # which swaylock can't (it collects input first, then runs PAM).
  hyprlockBin = "${pkgs.hyprlock}/bin/hyprlock --grace 0 --no-fade-in";

  # Deliberately unguarded: an orphaned hyprlock that has lost its surface but
  # not exited would otherwise make every lock path a no-op, which fails open.
  # Only before-sleep checks, since that is the one path that genuinely stacks.
  # The restart clears a stale fprintd claim left by a disconnect mid-verify,
  # which otherwise blocks later locks; safe once hyprlock has exited, not at
  # resume. Needs the polkit rule in modules/system/desktop.nix.
  lockCmd = pkgs.writeShellScript "lock" ''
    ${hyprlockBin}
    ${pkgs.systemd}/bin/systemctl restart fprintd.service || true
  '';

  # swayidle holds the sleep inhibitor until before-sleep exits, and hyprlock
  # has no daemonize flag, so running it directly would block suspend until
  # unlocked. Background it, then settle so it takes the lock before the
  # machine goes down — otherwise resume can flash the desktop.
  # Guarded here only: idling past both timers locks at 900s and then suspends
  # at 1800s, and the lid fires the sway bindswitch alongside this — stacking a
  # second hyprlock leaves a black screen that looks like a re-lock. Failing to
  # lock here is safe because the machine is suspending with a lock already up.
  sleepLockCmd = pkgs.writeShellScript "sleep-lock" ''
    ${pkgs.procps}/bin/pgrep -x hyprlock >/dev/null && exit 0
    ${lockCmd} &
    sleep 1
  '';

  # Controller input never reaches the compositor's seat, so swayidle counts a
  # gamepad session as idle and locks mid-game. Steam's "reaper SteamLaunch
  # AppId=..." process lives exactly as long as the game, so skip while it
  # exists. The timer only re-arms on the next input event after a game exits.
  #
  # Backgrounded, not exec'd: swayidle runs with -w ("wait for command to
  # finish"), so a foreground hyprlock blocks it until you unlock — and the
  # 1800s suspend timeout below never fires, leaving the machine awake on the
  # lock screen all night. swaylock's -f used to fork and return immediately,
  # which is why this only appeared after the hyprlock migration.
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
    theme = {
      name = "Nordic";
      package = pkgs.nordic;
    };
    # Set to `null` to let libadwaita apps render natively instead. GTK4
    # ignores gtk-theme-name, so home-manager writes a gtk.css that @imports
    # the theme; extraCss below is appended after, so it wins.
    gtk4.theme = config.gtk.theme;

    # Restore keyboard focus rings: Nordic's GTK4 sheet sets a universal
    # `* { outline-width: 0px; }`, leaving dialogs with no visible selection.
    # `*` has zero specificity, so any real selector beats it. Colour is Nord
    # frost #88c0d0, matching the sway focus border. GTK4 only — the GTK3 sheet
    # has no such rule and GTK3 has no :focus-visible anyway.
    #
    # Scoped to actual controls on purpose. A bare `:focus-visible` also matches
    # the toplevel and ghostty's terminal widget, which fills the window — that
    # drew a 2px ring in the same colour as the sway border just inside it, so
    # the window looked like it randomly grew a thicker border while typing
    # (`:focus-visible` is keyboard-only, hence the intermittence).
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
        outline-color: #88c0d0;
        outline-style: solid;
        outline-width: 2px;
        outline-offset: -2px;
      }

      /* Dialog action buttons (libadwaita puts them in .response-area) sit on a
         busy background, so add an inner ring to make the selection obvious. */
      .response-area button:focus-visible,
      .dialog-action-area button:focus-visible,
      dialog button:focus-visible {
        box-shadow: inset 0 0 0 2px rgba(136, 192, 208, 0.5);
      }
    '';

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

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

  # Modern cursor (the default is the chunky X11 fallback). sway also picks it
  # up via `seat seat0 xcursor_theme Bibata-Modern-Ice` in config/sway/config.
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
          # 1s rather than the 60s the clock itself needs: hyprlock only
          # re-evaluates the input field's placeholder on redraw, and this
          # timer is the only thing driving redraws on an idle lock screen.
          # At 30s the fingerprint icon took up to half a minute to appear.
          text = cmd[update:1000] date +"%H:%M"
          color = rgb(eceff4)
          font_size = 72
          font_family = JetBrainsMono Nerd Font
          position = 0, 150
          halign = center
          valign = center
      }

      label {
          monitor =
          text = cmd[update:30000] date +"%A, %e %B"
          color = rgb(d8dee9)
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
          inner_color = rgb(3b4252)
          outer_color = rgb(4c566a)
          check_color = rgb(88c0d0)
          fail_color = rgb(bf616a)
          font_color = rgb(eceff4)
          font_family = JetBrainsMono Nerd Font
          dots_size = 0.25
          dots_spacing = 0.3
          dots_rounding = -1
          # $FPRINTPROMPT expands to ready_message below, or to nothing once the
          # reader drops out — so the lock shows alone rather than claiming a
          # fingerprint that hyprlock has given up on (hyprwm/hyprlock#711).
          placeholder_text = <span size="24pt"> 󰌾$FPRINTPROMPT </span>
          fail_text = <i>$FAIL</i>
          fade_on_empty = false
      }

      auth {
          fingerprint {
              enabled = true
              ready_message = <span alpha="60%"> /</span> 󰈷
              present_message = <span alpha="60%"> /</span> 󰈷
          }
      }
    '';

    # Picks ghostty as the terminal for Terminal=true desktop entries, via
    # xdg-terminal-exec (packages.nix).
    "xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

    # sway compositor
    "sway/config".source = "${configDir}/sway/config";
    "sway/wallpaper.png".source = "${configDir}/wallpaper/wallpaper.png";
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
}
