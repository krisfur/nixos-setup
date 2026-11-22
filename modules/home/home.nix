{ pkgs, config, lib, inputs, ... }:

let
  configDir = ../../config;

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
    # Secret Service (served by KWallet), not Chromium's native KWallet backend:
    # the key migrated from gnome-keyring lives there, so old sessions decrypt.
    exec "$app" \
      --password-store=gnome-libsecret \
      --enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
      "$@"
  '';

  # CurseForge (Electron AppImage), same approach as Helium. Overwolf only ships
  # it zipped, and the zip lags the app; its updater fixes that on first run.
  curseforge = pkgs.writeShellScriptBin "curseforge" ''
    set -euo pipefail
    app="$HOME/Applications/curseforge.AppImage"
    if [ ! -x "$app" ]; then
      mkdir -p "$HOME/Applications"
      echo "Fetching latest CurseForge AppImage..." >&2
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      ${pkgs.curl}/bin/curl -fL \
        https://curseforge.overwolf.com/downloads/curseforge-latest-linux.zip \
        -o "$tmp/cf.zip"
      ${pkgs.unzip}/bin/unzip -q "$tmp/cf.zip" -d "$tmp"
      mv "$tmp"/*.AppImage "$app"
      chmod +x "$app"
    fi
    # The updater's relaunch dies with the appimage-run sandbox
    # (--die-with-parent), so relaunch here if the AppImage was replaced.
    before=$(${pkgs.coreutils}/bin/stat -c %Y "$app")
    "$app" "$@" || true
    if [ "$(${pkgs.coreutils}/bin/stat -c %Y "$app")" != "$before" ]; then
      exec "$app"
    fi
  '';

  # Keep the native install writable for self-updates; nix-ld supplies its loader.
  # Pin installer dependencies on PATH.
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
  imports = [ ./plasma.nix ];

  home.username = "kfurman";
  home.homeDirectory = "/home/kfurman";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  # ls colours come from LS_COLORS, not the ANSI palette, so directories can be
  # warm without repurposing an ANSI slot. Truecolor values, Dust palette.
  home.sessionVariables.LS_COLORS = lib.concatStringsSep ":" [
    "rs=0"
    "di=1;38;2;201;160;107"   # directories - sand, bold
    "ln=38;2;163;186;178"     # symlinks - muted teal
    "or=38;2;176;87;74"       # broken symlink - red
    "mi=38;2;176;87;74"       # missing target
    "ex=38;2;138;148;100"     # executables - olive
    "pi=38;2;138;112;80"      # fifo
    "so=38;2;163;117;122"     # socket
    "bd=38;2;217;169;92"      # block device
    "cd=38;2;217;169;92"      # char device
    "su=38;2;242;232;213;48;2;176;87;74"
    "sg=38;2;242;232;213;48;2;138;112;80"
    "tw=38;2;30;26;22;48;2;201;160;107"
    "ow=38;2;201;160;107"
    "st=38;2;221;208;186"
    # archives
    "*.tar=38;2;199;109;94" "*.tgz=38;2;199;109;94" "*.zip=38;2;199;109;94"
    "*.gz=38;2;199;109;94" "*.xz=38;2;199;109;94" "*.zst=38;2;199;109;94"
    "*.bz2=38;2;199;109;94" "*.7z=38;2;199;109;94" "*.rar=38;2;199;109;94"
    # media
    "*.jpg=38;2;163;117;122" "*.jpeg=38;2;163;117;122" "*.png=38;2;163;117;122"
    "*.gif=38;2;163;117;122" "*.webp=38;2;163;117;122" "*.svg=38;2;163;117;122"
    "*.mp4=38;2;187;143;147" "*.mkv=38;2;187;143;147" "*.webm=38;2;187;143;147"
    "*.mp3=38;2;163;186;178" "*.flac=38;2;163;186;178" "*.wav=38;2;163;186;178"
    # docs
    "*.pdf=38;2;217;169;92" "*.md=38;2;232;220;198" "*.txt=38;2;221;208;186"
  ];

  home.packages = [ helium curseforge claude pkgs.bubblewrap ];

  # Desktop entry so Helium shows in the launcher and as the default browser.
  xdg.desktopEntries.helium = {
    name = "Helium";
    genericName = "Web Browser";
    exec = "helium %U";
    # Upstream logo, pinned: the self-updating AppImage's own icon isn't installed.
    icon = "${pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/imputnet/helium/6881a552278c3c2c8ab56163bed3c3346dbf0fb8/resources/branding/product_logo.svg";
      hash = "sha256-3oNc4omimGTv7xHLpQ6HaXrUaGj5J4cgkaO36q+zHWI=";
    }}";
    categories = [ "Network" "WebBrowser" ];
    mimeType = [ "text/html" "x-scheme-handler/http" "x-scheme-handler/https" ];
  };
  # The scheme handlers carry login and "Install" links from the browser.
  xdg.desktopEntries.curseforge = {
    name = "CurseForge";
    exec = "curseforge %U";
    # The app's icon (white anvil on black) rebuilt from Simple Icons' pinned
    # glyph; the AppImage's own only exists after its "latest" download.
    icon = "${pkgs.runCommand "curseforge-icon.svg" {
      glyph = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/simple-icons/simple-icons/ae32bce73c78509a49cc132daa0df4c406f917e8/icons/curseforge.svg";
        hash = "sha256-VUY8mP5DuXaKY2wWLqwTFQFo+Vm2xMVVOgFnbgurobo=";
      };
    } ''
      d=$(${pkgs.gnused}/bin/sed -n 's/.*<path d="\([^"]*\)".*/\1/p' "$glyph")
      echo "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\"><rect width=\"24\" height=\"24\" rx=\"5.5\" fill=\"#111\"/><path transform=\"translate(4.2 4.2) scale(0.65)\" fill=\"#fff\" d=\"$d\"/></svg>" > $out
    ''}";
    categories = [ "Game" ];
    mimeType = [
      "x-scheme-handler/curseforge"
      "x-scheme-handler/cfauth"
      "x-scheme-handler/curseforge-checkout"
    ];
    settings.StartupWMClass = "CurseForge";
  };
  # NOT xdg.mimeApps: that symlinks mimeapps.list into the store read-only, and
  # every "open with -> set as default" writes through GIO to that same file, so
  # Thunar (and any other file manager) fails with EROFS. Seed a real file
  # instead and enforce only the keys we care about, leaving whatever the file
  # manager adds intact.
  home.activation.mimeDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.xdg.configHome}/mimeapps.list" <<'EOF'
    import configparser, os, sys
    path = sys.argv[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # a leftover store symlink from a previous xdg.mimeApps generation is
    # read-only; drop it before writing
    if os.path.islink(path):
        os.unlink(path)
    cp = configparser.ConfigParser()
    cp.optionxform = str
    cp.read(path)
    if "Default Applications" not in cp:
        cp["Default Applications"] = {}
    for mime in ("text/html", "x-scheme-handler/http", "x-scheme-handler/https"):
        cp["Default Applications"][mime] = "helium.desktop"
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
    EOF
  '';

  # Shadows the stock desktop entry, keeping its X-TerminalArg* keys. The
  # single-instance setting lives in config/ghostty/config, not on the exec
  # line, so every launch path agrees - except the Thunar terminal helper, which
  # must override it to keep its working directory (see the .desktop in
  # config/xfce4/helpers).
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

  # --- GTK / icon theming ---
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
      # Folder colour comes from the overlay in modules/system/desktop.nix.
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

  # Plasma's GTK sync and kconf_update scripts may replace these store symlinks;
  # force lets the next activation restore them instead of aborting.
  gtk.gtk2.force = true;
  xdg.configFile."gtk-3.0/settings.ini".force = true;
  xdg.configFile."gtk-3.0/gtk.css".force = true;
  xdg.configFile."gtk-4.0/settings.ini".force = true;
  xdg.configFile."gtk-4.0/gtk.css".force = true;

  # Keep global instructions separate from this repository's AGENTS.md.
  home.file.".claude/CLAUDE.md" = {
    source = "${configDir}/claude/instructions.md";
    force = true;
  };
  home.file.".claude/themes/dust.json".source = "${configDir}/claude/dust.json";

  # Merge the theme into writable settings, preserving other preferences.
  home.activation.claudeTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.python3}/bin/python3 - "${config.home.homeDirectory}/.claude/settings.json" <<'EOF'
    import json, os, sys
    path = sys.argv[1]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        cfg = {}
    cfg["theme"] = "custom:dust"
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    EOF
  '';

  # Modern cursor (the default is the chunky X11 fallback).
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

    # ghostty terminal (default window size bumped so btop fits)
    "ghostty/config".source = "${configDir}/ghostty/config";

    # Picks ghostty as the terminal for Terminal=true desktop entries, via
    # xdg-terminal-exec (packages.nix).
    "xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

    # neovim (flake input -> github.com/krisfur/neovim-config)
    "nvim/init.lua".source = "${inputs.neovim-config}/init.lua";
  };

  # Speaker DSP: the P14s speakers are tuned for Windows' Dolby driver and sound
  # tinny without it. A PipeWire filter-chain hosting the LSP and Calf LV2
  # plugins, pinned to the internal speaker sink so headphones and DACs play
  # untouched. Loaded into the running pipewire daemon, so it costs no extra
  # process; LV2_PATH comes from services.pipewire.extraLv2Packages in
  # desktop.nix.
  xdg.configFile."pipewire/pipewire.conf.d/99-thinkpad-unsuck.conf".source =
    "${configDir}/pipewire/thinkpad-unsuck.conf";

  # Thunar resolves Open Terminal Here through exo-open -> xfce4-mime-helper,
  # which reads this pair: helpers.rc names the helper, the .desktop defines how
  # to run it. Both packages come from desktop.nix.
  xdg.dataFile."xfce4/helpers/ghostty.desktop".source =
    "${configDir}/xfce4/helpers/ghostty.desktop";

  xdg.configFile."xfce4/helpers.rc".text = "TerminalEmulator=ghostty\n";

  # KDE colour scheme in the Dust palette, for Qt apps that pick a scheme by
  # name rather than following the platform theme.
  xdg.dataFile."color-schemes/Dust.colors".source =
    "${configDir}/color-schemes/Dust.colors";
}
