{ config, lib, pkgs, ... }:

# KDE Plasma user settings via plasma-manager. Carries over the old sway session's
# bindings, idle/lid behaviour, and Dust look. Only keys set here are managed;
# anything changed in System Settings persists alongside them.
let
  # Interpolated so the image gets its own store path; a bare path inside the
  # flake source isn't kept in the closure and Plasma found nothing there.
  wallpaper = "${../../config/wallpaper/wallpaper.jpg}";

  # UK-layout shifted digits: KWin may register Meta+Shift+1 as Meta+!.
  shiftedDigits = [
    "!"
    "\""
    "£"
    "$"
    "%"
    "^"
    "&"
    "*"
    "("
    ")"
  ];
  # Desktops beyond desktopCount are written too, unbound, so keys left from a
  # larger count don't linger (only managed keys are ever rewritten).
  desktopCount = 2;
  desktops = builtins.genList (i: i + 1) 10;
  used = n: n <= desktopCount;
  digit = n: toString (if n == 10 then 0 else n);
  perDesktop = f: builtins.listToAttrs (map f desktops);
in
{
  programs.plasma = {
    enable = true;

    workspace = {
      # Breeze ("default") follows the colour scheme; breeze-dark would not.
      theme = "default";
      colorScheme = "Dust"; # config/color-schemes/Dust.colors, installed in home.nix
      iconTheme = "Papirus-Dark";
      cursor = {
        theme = "Bibata-Modern-Classic";
        size = 24;
      };
      inherit wallpaper;
    };

    # The wallpaper script otherwise runs only when its content changes, so a
    # screen first seen later (the external monitor) kept KDE's stock image.
    # Plasma keeps a desktop per screen ever seen, so every login covers them.
    startup.desktopScript."wallpaper_picture".runAlways = true;

    fonts.fixedWidth = {
      family = "JetBrainsMono Nerd Font";
      pointSize = 10;
    };

    # Plasma's stock panel (plasma-desktop's defaultPanel layout template).
    panels = [
      {
        location = "bottom";
        # Not floating: the floating margin pushed the launcher in from the edge.
        floating = false;
        height = 44;
        widgets = [
          # Dust-coloured NixOS logo, shared with fastfetch.
          { kickoff.icon = "${../../config/fastfetch/logo.png}"; }
          {
            pager.general = {
              showWindowOutlines = true;
              showApplicationIconsOnWindowOutlines = true;
            };
          }
          # Pinned apps, replacing the stock Settings/Dolphin/browser pins.
          {
            iconTasks.launchers = [
              "applications:helium.desktop"
              "applications:discord.desktop"
              "applications:steam.desktop"
              "applications:com.mitchellh.ghostty.desktop"
            ];
          }
          "org.kde.plasma.marginsseparator"
          # Labelled CPU / RAM rows; the stock ring presets were unlabelled and
          # indistinguishable.
          {
            systemMonitor = {
              displayStyle = "org.kde.ksysguard.textonly";
              sensors = [
                {
                  name = "cpu/all/usage";
                  label = "CPU";
                  color = "201,160,107";
                }
                {
                  name = "memory/physical/used";
                  label = "RAM";
                  color = "163,186,178";
                }
              ];
              textOnlySensors = [
                "cpu/all/averageTemperature"
                "memory/physical/total"
              ];
            };
          }
          # plasma-manager can't configure tray items yet (items.configs is a
          # no-op), so the battery sits on the panel and the tray's copy is hidden.
          { systemTray.items.hidden = [ "org.kde.plasma.battery" ]; }
          { battery.showPercentage = true; }
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];

    input = {
      keyboard = {
        layouts = [ { layout = "gb"; } ];
        numlockOnStartup = "on";
      };
      # KDE stores libinput settings per device; IDs from /proc/bus/input/devices.
      touchpads = [
        {
          name = "ELAN0676:00 04F3:3195 Touchpad";
          vendorId = "04f3";
          productId = "3195";
          naturalScroll = true;
        }
      ];
      mice = [
        {
          name = "TPPS/2 Elan TrackPoint";
          vendorId = "0002";
          productId = "000a";
          naturalScroll = true;
        }
        {
          name = "Razer Orochi V2";
          vendorId = "1532";
          productId = "0094";
          naturalScroll = true;
        }
      ];
    };

    kwin = {
      virtualDesktops = {
        number = desktopCount;
        rows = 1;
      };
      # Plasma 6.1's edge barrier fights moving the pointer to the side screen.
      edgeBarrier = 0;
      cornerBarrier = false;
      # Instant desktop switches.
      effects.desktopSwitching.animation = "off";
    };

    # Idle timings carried over from sway: lock 15 min, screen off 20, suspend 30.
    kscreenlocker = {
      autoLock = true;
      timeout = 15;
      lockOnResume = true;
      appearance.wallpaper = wallpaper;
    };
    powerdevil =
      let
        profile = {
          turnOffDisplay.idleTimeout = 1200;
          autoSuspend = {
            action = "sleep";
            idleTimeout = 1800;
          };
          whenLaptopLidClosed = "sleep";
          inhibitLidActionWhenExternalMonitorConnected = true;
          # powerProfile left unset: power-profile-on-ac in core.nix owns it.
        };
      in
      {
        AC = profile;
        battery = profile;
      };

    hotkeys.commands = {
      launch-terminal = {
        name = "Launch Ghostty";
        key = "Meta+Return";
        # Asks the running instance over D-Bus (or D-Bus-activates one) rather
        # than initialising GTK in a new process first: ~150 ms vs ~270 ms.
        command = "ghostty +new-window";
      };
      launch-browser = {
        name = "Launch Helium";
        key = "Meta+B";
        command = "helium";
      };
    };

    spectacle.shortcuts = {
      launch = [ ];
      captureRectangularRegion = "Print";
      captureCurrentMonitor = "Meta+Shift+Print";
      captureActiveWindow = "Meta+Print";
    };

    # The old sway bindings. Arrows focus; Shift+arrows tile (and cross screens on a
    # repeat press); Alt+arrows resize. Desktops 1-10 replace taskbar entries.
    shortcuts = {
      kwin = {
        "Window Close" = [
          "Alt+F4"
          "Meta+W"
        ];
        "Overview" = "Meta+O"; # default Meta+W, taken by close
        "Window Maximize" = [
          "Meta+PgUp"
          "Meta+F"
        ];
        "Window Fullscreen" = "Meta+Shift+F";

        "Switch Window Left" = "Meta+Left";
        "Switch Window Right" = "Meta+Right";
        "Switch Window Up" = "Meta+Up";
        "Switch Window Down" = "Meta+Down";

        "Window Quick Tile Left" = "Meta+Shift+Left";
        "Window Quick Tile Right" = "Meta+Shift+Right";
        "Window Quick Tile Top" = "Meta+Shift+Up";
        "Window Quick Tile Bottom" = "Meta+Shift+Down";
        "Window to Next Screen" = [ ];
        "Window to Previous Screen" = [ ];

        "Window Grow Horizontal" = "Meta+Alt+Right";
        "Window Shrink Horizontal" = "Meta+Alt+Left";
        "Window Grow Vertical" = "Meta+Alt+Down";
        "Window Shrink Vertical" = "Meta+Alt+Up";
      }
      // perDesktop (n: {
        name = "Switch to Desktop ${toString n}";
        value = if used n then "Meta+${digit n}" else [ ];
      })
      // perDesktop (n: {
        name = "Window to Desktop ${toString n}";
        value =
          if used n then
            [
              "Meta+Shift+${digit n}"
              "Meta+${builtins.elemAt shiftedDigits (n - 1)}"
            ]
          else
            [ ];
      });

      # Meta+N goes to desktops where one exists, else back to KDE's taskbar default.
      plasmashell = perDesktop (n: {
        name = "activate task manager entry ${toString n}";
        value = if used n then [ ] else "Meta+${digit n}";
      });

      ksmserver."Log Out" = [
        "Ctrl+Alt+Del"
        "Meta+M"
      ];
      "services/org.kde.krunner.desktop"."_launch" = [
        "Alt+Space"
        "Meta+Space"
      ];
    };

    configFile = {
      kwinrc.Windows = {
        FocusPolicy = "FocusFollowsMouse";
        NextFocusPrefersMouse = true;
      };

      # Plasma's default, set explicitly because an earlier generation wrote
      # false (tried for the dual-screen WoW stutter; didn't help, see
      # KWIN_DRM_NO_DIRECT_SCANOUT below).
      kwinrc.Compositing.AllowTearing = true;

      # kde-gtk-config would rewrite the home-manager GTK theme and gtk.css.
      kded5rc."Module-gtkconfig".autoload = false;

      # KWallet holds all secrets, unlocked at login by pam_kwallet (desktop.nix),
      # and serves libsecret apps (gh, Helium, Proton) via the Secret Service API.
      # Enabled is set explicitly: an earlier generation wrote false.
      kwalletrc = {
        # pam_kwallet5 only unlocks "kdewallet"; the Secret Service migration
        # had created and defaulted to "Default Keyring".
        Wallet = {
          Enabled = true;
          "Default Wallet" = "kdewallet";
        };
        "org.freedesktop.secrets".apiEnabled = true;
      };

      kdeglobals = {
        General = {
          TerminalApplication = "ghostty";
          TerminalService = "com.mitchellh.ghostty.desktop";
        };
        # Instant animations everywhere (System Settings' speed slider at max).
        KDE.AnimationDurationFactor = 0;
      };

      # X11 apps "scaled by the system": render at 1x, KWin scales per screen.
      # The default (apply scaling themselves) makes KWin force Xwayland to the
      # highest screen scale (the panel's 1.1), overwriting Scale, so WoW drew
      # 2816x1584 on the 1440p monitor and KWin downscaled every frame. Only
      # Steam's client is X11 otherwise; it's merely a bit soft on the panel.
      kwinrc.Xwayland = {
        XwaylandClientsScale = false;
        Scale = 1;
      };

      # Save to ~/Pictures/Screenshots and copy to the clipboard.
      spectaclerc = {
        General = {
          autoSaveImage = true;
          clipboardGroup = "PostScreenshotCopyImage";
        };
        ImageSave.imageSaveLocation = "file://${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };
  };

  # With both screens on, focused fullscreen WoW stalled ~40 ms once a second
  # (fine with one screen; not tearing, refresh rate, X11 path or input).
  # No direct scanout keeps KWin compositing it, which fixed it. Costs one GPU
  # copy per frame for fullscreen games.
  systemd.user.sessionVariables.KWIN_DRM_NO_DIRECT_SCANOUT = "1";

  # Both units stop in parallel at logout. The panel's CPU/RAM widget then tries
  # to reactivate ksystemstats, is refused, and plasmashell hung 40 s until
  # SIGKILL. Ordering After= makes plasmashell stop first (stops run in reverse).
  # It still hung once without that widget (stuck after "QObject::disconnect:
  # Unexpected nullptr parameter"), so cap the wait at 10 s and abort rather
  # than kill: the coredump (`coredumpctl info plasmashell`) shows where it hangs.
  xdg.configFile."systemd/user/plasma-plasmashell.service.d/stop-before-ksystemstats.conf".text = ''
    [Unit]
    After=plasma-ksystemstats.service

    [Service]
    TimeoutStopSec=10s
    TimeoutStopFailureMode=abort
  '';

  # Built-in panel at 110%. KWin owns kwinoutputconfig.json (per-screen entries,
  # rewritten on display changes), so patch only eDP scales instead of managing
  # the file. Takes effect at next login; a fresh machine needs one login first.
  home.activation.panelScale = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.xdg.configHome}/kwinoutputconfig.json" <<'EOF'
    import json, os, sys
    path = sys.argv[1]
    if not os.path.exists(path):
        sys.exit(0)
    with open(path) as f:
        cfg = json.load(f)
    changed = False
    for section in cfg:
        if section.get("name") != "outputs":
            continue
        for out in section.get("data", []):
            if out.get("connectorName", "").startswith("eDP") and out.get("scale") != 1.1:
                out["scale"] = 1.1
                changed = True
    if changed:
        with open(path, "w") as f:
            json.dump(cfg, f, indent=4)
    EOF
  '';
}
