{ pkgs, config, ... }:

# KDE Plasma user settings via plasma-manager. Mirrors the sway session's
# bindings, idle/lid behaviour, and Dust look. Only keys set here are managed;
# anything changed in System Settings persists alongside them.
let
  wallpaper = ../../config/wallpaper/wallpaper.jpg;

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
  desktops = builtins.genList (i: i + 1) 10;
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

    fonts.fixedWidth = {
      family = "JetBrainsMono Nerd Font";
      pointSize = 10;
    };

    # Top bar in the waybar layout: desktops left, clock centre, tray right.
    panels = [
      {
        location = "top";
        height = 36;
        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.pager"
          { iconTasks.launchers = [ ]; }
          "org.kde.plasma.panelspacer"
          { digitalClock.time.format = "24h"; }
          "org.kde.plasma.panelspacer"
          "org.kde.plasma.systemtray"
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
        number = 10;
        rows = 1;
      };
      # Plasma 6.1's edge barrier fights moving the pointer to the side screen.
      edgeBarrier = 0;
      cornerBarrier = false;
    };

    # Same idle timings as swayidle: lock 15 min, screen off 20, suspend 30.
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
        command = "ghostty";
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

    # Sway's bindings. Arrows focus; Shift+arrows tile (and cross screens on a
    # repeat press); Alt+arrows resize. Desktops 1-10 replace taskbar entries.
    shortcuts = {
      kwin = {
        "Window Close" = [
          "Alt+F4"
          "Meta+W"
        ];
        "Overview" = "Meta+O"; # default Meta+W, taken by close
        "Window Fullscreen" = "Meta+F";

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
        value = "Meta+${digit n}";
      })
      // perDesktop (n: {
        name = "Window to Desktop ${toString n}";
        value = [
          "Meta+Shift+${digit n}"
          "Meta+${builtins.elemAt shiftedDigits (n - 1)}"
        ];
      });

      plasmashell = perDesktop (n: {
        name = "activate task manager entry ${toString n}";
        value = [ ];
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

      # kde-gtk-config would rewrite the home-manager GTK theme and gtk.css.
      kded5rc."Module-gtkconfig".autoload = false;

      # Secrets stay in gnome-keyring (unlocked by greetd's PAM), as under sway.
      kwalletrc.Wallet.Enabled = false;

      kdeglobals.General = {
        TerminalApplication = "ghostty";
        TerminalService = "com.mitchellh.ghostty.desktop";
      };

      # Match sway-screenshot.sh: save to ~/Pictures/Screenshots and copy.
      spectaclerc = {
        General = {
          autoSaveImage = true;
          clipboardGroup = "PostScreenshotCopyImage";
        };
        ImageSave.imageSaveLocation = "file://${config.home.homeDirectory}/Pictures/Screenshots";
      };
    };

    # Adopt the PAM-unlocked keyring before D-Bus activates a locked second one
    # (same race the sway autostart handles).
    startup.startupScript.gnome-keyring = {
      text = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --components=secrets,ssh,pkcs11";
      runAlways = true;
    };
  };
}
