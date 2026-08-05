# NixOS module: Omarchy system integration (Stage 3).
#
# Wires the vendored upstream tree (OMARCHY_PATH) as a session variable, adds
# the Quattro runtime dependencies, and enables a uwsm-managed Hyprland
# session driven by the Hyprland flake package (>= 0.56 for the Lua config).
#
# This module is pure NixOS (no flake inputs referenced directly). The flake's
# `nixosModules.default` wrapper injects `omarchy.package` and the Hyprland
# package defaults, so a consumer just does:
#
#   imports = [ omarchy-nix.nixosModules.default ];
#   omarchy.enable = true;
#
# Everything below is guarded by `mkIf cfg.enable`, so importing the module is
# side-effect-free until the consumer opts in.
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.omarchy;

  # Validators/serializers for user-controlled option values:
  # Lua string escaping for monitors.lua and environment.d(5) escaping for
  # the identity variables below.
  fmt = import ../lib/omarchy-formats.nix { inherit lib; };

  # Map an omarchy.exclude_packages entry (a package *attribute name* string,
  # e.g. "obsidian") to the same form a derivation exposes. We match on both
  # `pname` (preferred, e.g. "obsidian") and `name` (fallback, may carry a
  # version suffix like "obsidian-1.5.0"). This keeps exclude_packages working
  # for any package regardless of how its derivation names itself.
  pkgAttrName =
    p:
    let
      # pname is the clean attribute name when the derivation sets it;
      # otherwise strip a trailing -<version> from name.
      base = p.pname or (builtins.head (lib.splitString "-" (p.name or "")));
    in
    base;

  excluded = builtins.map (n: n) cfg.exclude_packages;

  # Drop packages whose attribute name appears in omarchy.exclude_packages.
  filterExcluded = lib.filter (p: !builtins.elem (pkgAttrName p) excluded);

  # Menu-managed packages (omarchy-packages.json), read once and shared by
  # the (B0) unfree whitelist and the (B0b) managed-packages block. A missing
  # or null file means empty sets. The catalog ships inside cfg.package
  # (nix-catalog.json, see pkgs/omarchy-catalog.nix).
  managed =
    if cfg.managedPackagesFile != null && builtins.pathExists cfg.managedPackagesFile then
      builtins.fromJSON (builtins.readFile cfg.managedPackagesFile)
    else
      { };
  managedPkgs = managed.packages or [ ];
  managedFeatures = managed.features or [ ];

  # Menu Install/Remove catalog — imported statically (same repo as the
  # package's share/omarchy/nix-catalog.json, which the runtime scripts
  # read). MUST NOT be read from cfg.package: the (B0)/(B0b) computations
  # below feed nixpkgs.config.* (allowUnfreePredicate, permittedInsecure-
  # Packages, problems.handlers), and reading the catalog via cfg.package
  # closes a recursion loop — nixpkgs.config → catalogJson → omarchy.package
  # → the flake wrapper's pkgs.system → config.nixpkgs.pkgs → nixpkgs.config.
  # Latent on 26.05: owned pkgs + non-empty omarchy-packages.json made even
  # system.build.toplevel hit infinite recursion.
  catalogJson = import ../../pkgs/omarchy-catalog.nix;

  # Literal lib.getName strings / insecure name-versions from catalog entries
  # whose pkgs appear in the managed JSON (and from selected features). Used
  # to extend the (B0) whitelist / permittedInsecurePackages with exactly what
  # the JSON actually manages — including hidden deps (steam-unwrapped,
  # firefox-bin-unwrapped, openssl-1.1.1w, electron-…). Literals avoid
  # lib.getName pkgs.${n} at config-construction time (throw-aliases, cycles).
  managedUnfreeNames = lib.unique (
    lib.concatMap (
      attr:
      lib.concatMap (e: lib.optionals (builtins.elem attr (e.pkgs or [ ])) (e.unfreeNames or [ ])) (
        builtins.attrValues catalogJson.entries
      )
    ) managedPkgs
    ++ lib.concatMap (f: catalogJson.features.${f}.unfreeNames or [ ]) managedFeatures
  );
  managedInsecureNames = lib.unique (
    lib.concatMap (
      attr:
      lib.concatMap (e: lib.optionals (builtins.elem attr (e.pkgs or [ ])) (e.insecureNames or [ ])) (
        builtins.attrValues catalogJson.entries
      )
    ) managedPkgs
  );
  # "<pname>.<problem>" keys for nixpkgs.config.problems.handlers (newer
  # nixpkgs marks some catalog pkgs broken, e.g. sublimetext4). Scoped opt-in
  # as "warn" — only when the entry is selected. On nixpkgs without the
  # problems mechanism the freeform nixpkgs.config swallows it harmlessly.
  managedProblemHandlers = lib.unique (
    lib.concatMap (
      attr:
      lib.concatMap (e: lib.optionals (builtins.elem attr (e.pkgs or [ ])) (e.problemHandlers or [ ])) (
        builtins.attrValues catalogJson.entries
      )
    ) managedPkgs
  );

  # Feature name -> config applied when the name appears in the JSON. The
  # NixOS-native analogue of what upstream install scripts wire by hand.
  # mkDefault so a consumer's own explicit config wins.
  managedFeatureDefs = {
    steam = {
      programs.steam.enable = lib.mkDefault true;
    };
    tailscale = {
      services.tailscale.enable = lib.mkDefault true;
    };
    onepassword = {
      programs._1password.enable = lib.mkDefault true;
      programs._1password-gui.enable = lib.mkDefault true;
    };
    ollama = {
      services.ollama.enable = lib.mkDefault true;
    };
    xpadneo = {
      # Menu Install -> Gaming -> Xbox Controllers: the NixOS
      # module ships the kernel module, loads it, enables bluetooth, and
      # blacklists nothing — the Arch script's modprobe//etc writes are
      # quarantined.
      hardware.xpadneo.enable = lib.mkDefault true;
    };
  };

  # Cursor fallback: upstream sets no cursor theme name (only
  # XCURSOR_SIZE/HYPRCURSOR_SIZE=24), so libxcursor resolves the theme named
  # "default" via icons/default/index.theme. On Arch that directory exists
  # with `Inherits=Adwaita` (verified on the upstream Arch reference
  # install). NixOS provides no
  # such dir, leaving the pointer invisible; replicate it here.
  xcursorDefaultAdwaita = pkgs.runCommand "xcursor-default-adwaita" { } ''
    mkdir -p "$out/share/icons/default"
    cat > "$out/share/icons/default/index.theme" <<'EOF'
    [Icon Theme]
    Inherits=Adwaita
    EOF
  '';

  # Core desktop-session runtime set, derived from upstream's
  # `install/omarchy-base.packages` (fetched read-only from the live
  # upstream reference box). Full upstream package parity is now the policy —
  # including the heavier apps (libreoffice, obs, dev toolchains) that upstream
  # ships by default. Grouped by role so the rationale for each inclusion is
  # local to its line.
  runtimeDeps =
    with pkgs;
    filterExcluded (
      [
        # --- Terminal / shell session ---
        foot
        xdg-terminal-exec
        bat
        eza
        fd
        fzf
        ripgrep
        zoxide
        starship
        tmux
        jq
        util-linux # flock: omarchy-nix-add/remove transaction lock
        gum
        tldr
        fastfetch
        less

        # --- Audio / video stack (pipewire + wireplumber is the session core) ---
        pipewire
        wireplumber
        # pactl CLI: omarchy-audio-* scripts resolve sinks via
        # `pactl get-default-sink` / set-sink-volume. pipewire.pulse provides
        # the Pulse protocol socket, not the CLI binary (issue #1).
        pulseaudio
        pamixer
        alsa-utils
        playerctl
        # mpv ships with the mpris script upstream; mpvScripts.mpris standalone
        # is a no-op unless injected via override.
        (mpv.override { scripts = [ mpvScripts.mpris ]; })

        # --- Network / Bluetooth ---
        networkmanager
        bluez
        bluez-tools
        avahi
        nssmdns

        # --- Wayland capture / picker / clipboard ---
        grim
        slurp
        hyprpicker
        hyprsunset
        wl-clipboard
        wtype
        xdg-desktop-portal-gtk

        # --- Cursor theme: upstream sets no cursor theme name (only
        # XCURSOR_SIZE/HYPRCURSOR_SIZE=24) and on Arch gets Adwaita cursors
        # transitively via gnome-themes-extra. We ship no cursor package by
        # default, so Hyprland cursor resolution falls back to the invisible
        # default. adwaita-icon-theme provides the cursors; no theme name env
        # var is set to stay at parity with upstream. ---
        adwaita-icon-theme

        # --- Quattro shell: the whole desktop (bar, launcher, menus,
        # notifications, OSDs, lock, polkit) is a single quickshell process
        # launched from Hyprland autostart. Without it there is no shell. ---
        quickshell

        # gtk-launch: the quickshell launcher (shell/services/AppLibrary.qml)
        # starts every picked app via `gtk-launch <desktop-id>`. gtk3 is
        # already in the closure via nautilus/evince — this just puts its bin
        # on PATH. Without it the launcher OSD says "Launching X…" and the
        # app silently never starts.
        gtk3

        # --- Dictation (voxtype). Upstream ships voxtype via an opt-in
        # invitation / Install → AI → Dictation (omarchy-voxtype-install);
        # we ship the package declaratively so it is present by default.
        # default/hypr/bindings/voxtype.lua binds F9 + Super+Ctrl+X when the
        # binary is on PATH. [output] mode = "type" types via ydotool (daemon
        # enabled above); the whisper model (~150MB) downloads on first
        # `voxtype setup --download` (still run via omarchy-voxtype-install). ---
        voxtype
        # Arch voxtype-bin installs packaging/voxtype-configure.desktop so
        # Super+Space → Apps shows "Voxtype Configuration" (TUI via
        # voxtype-configure-launcher). nixpkgs' voxtype omits that entry;
        # ship the omarchy equivalent so the launcher matches Arch.
        (pkgs.makeDesktopItem {
          name = "voxtype-configure";
          desktopName = "Voxtype Configuration";
          genericName = "Voice-to-Text Settings";
          comment = "Configure voxtype dictation settings (engine, model, hotkey, audio, output)";
          exec = "omarchy-voxtype-config";
          icon = "audio-input-microphone";
          categories = [ "Settings" ];
          startupWMClass = "voxtype";
          keywords = [
            "voxtype"
            "voice"
            "dictation"
            "transcription"
            "whisper"
            "settings"
            "configuration"
          ];
        })
        ydotool

        # --- Default browser (upstream parity). bin/omarchy-finalize-user
        # runs `xdg-settings set default-web-browser chromium.desktop`; the
        # HM module mirrors that. exclude_packages still works. ---
        chromium

        # --- File manager / document viewers / image tools ---
        nautilus
        evince
        imv
        imagemagick

        # --- Input method (fcitx5). The Qt integration module is not a
        # top-level attribute; it lives under the Qt package scopes. We pull
        # the Qt5 build for broad app compatibility (Qt5 is still the common
        # case on a desktop; add qt6Packages.fcitx5-qt later if needed). ---
        fcitx5
        fcitx5-gtk
        libsForQt5.fcitx5-qt

        # --- Power / brightness ---
        brightnessctl
        power-profiles-daemon

        # --- Fonts (Nerd Font + CJK + emoji coverage). noto-fonts-cjk was
        # split upstream into -sans/-serif; we ship the sans set which is what
        # a default desktop wants. Emoji is noto-fonts-color-emoji. The Nerd
        # Font is selected by member attribute (nerd-fonts.<name>) since the
        # upstream package was refactored from a single .override-able bundle
        # into one derivation per font family. ---
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        nerd-fonts.jetbrains-mono

        # --- Misc utilities used across bin/omarchy-* scripts ---
        socat
        inotify-tools
        # parted: fish format-drive.fish partitioning (omarchy-fish profile).
        parted
        # rsync: fish rsw rsync-on-change watchers (explicit — not just
        # environment.defaultPackages).
        rsync
        # file: fish ff.fish Kitty preview branch calls `file --mime-type`.
        file
        # iw: omarchy-network-band (Wi-Fi band toggle in the network panel,
        # quattro 14f1bb6c) shells out to `iw dev <device> link`.
        iw
        # qrencode: omarchy-network-qr renders the Wi-Fi QR matrix (Setup >
        # Network > QR Code). ddcutil: omarchy-brightness-display-ddc drives
        # external monitor brightness over DDC/CI (needs hardware.i2c, below).
        qrencode
        ddcutil
        plocate
        libnotify
        # fwupdmgr for omarchy-update-firmware (service enabled in parity block).
        fwupd

        # --- first-run / finalize-user runtime (install/user/*) ---
        # gsettings CLI + org.gnome.desktop.interface schemas (gnome-theme.sh,
        # gtk-primary-paste.sh). programs.dconf.enable (below) provides the
        # dconf backend those writes need.
        glib
        gsettings-desktop-schemas
        # Adwaita-dark gtk theme dir (gnome-theme.sh sets gtk-theme to it).
        gnome-themes-extra
        # Yaru-* icon themes: shipped via omarchy.appPackages (pkgs/yaru-theme.nix),
        # not pkgs.yaru-theme — nixpkgs removed that attr (murrine/GTK2, 2026-07-22).
        # xdg-user-dirs-update (finalize-user) + update-desktop-database
        # (omarchy-refresh-applications) + git config (install/user/git.sh).
        xdg-user-dirs
        desktop-file-utils
        git
        # xdg-settings / xdg-mime (finalize-user default browser + mailto).
        xdg-utils
        # ffmpeg/ffprobe on PATH: omacut shells out to them for the actual
        # cut/export (upstream README). Also used by omarchy media scripts
        # (omarchy-transcode).
        ffmpeg

        # --- Upstream parity: terminal / CLI tools ---
        neovim
        btop
        lazygit
        lazydocker
        yt-dlp
        # dua is the upstream disk-usage tool (dua-cli was renamed to dua).
        dua
        inxi
        man-db
        unzip
        whois
        bash-completion
        inetutils
        dosfstools
        exfatprogs
        tesseract5
        tree-sitter
        cliamp
        tzupdate
        usage
        lua5_1
        luarocks

        # --- Upstream parity: GUI apps ---
        obs-studio
        libreoffice-fresh
        kdePackages.kdenlive
        obsidian
        pinta
        xournalpp
        localsend
        moonlight-qt
        # omacalc replaced gnome-calculator upstream (quattro "Switch to
        # Omacalc"); it ships via omarchy.appPackages (pkgs/omacalc.nix).
        gnome-disk-utility
        # sushi (not gnome-sushi — the attr was renamed upstream).
        sushi

        # --- Upstream parity: Nautilus / GVfs stack ---
        ffmpegthumbnailer
        gvfs
        nautilus-python

        # --- Upstream parity: client / dev libraries ---
        libsecret
        postgresql.lib
        mariadb-connector-c
        python3Packages.pygobject3
        python3Packages.poetry-core
        python3Packages.terminaltexteffects

        # --- Upstream parity: dev toolchains ---
        # (rust removed upstream from base packages: "We don't need rust any
        # longer"; the Rust dev env stays available via the Install menu.)
        clang
        llvm
        ruby
        dotnet-runtime
        mise

        # --- Upstream parity: automount ---
        udiskie

        # --- Upstream parity: screen recording + printing UI ---
        # gpu-screen-recorder is NOT a bare runtimeDeps entry: its KMS capture
        # backend needs gsr-kms-server with cap_sys_admin, which a store path
        # cannot carry. programs.gpu-screen-recorder.enable (below, B2) adds
        # the package + the setcap security wrapper.
        # system-config-printer: the CUPS printer GUI + queue applet upstream
        # ships for the printing service. nixpkgs names the applet binary
        # system-config-printer-applet (Arch: print-applet) and ships its
        # /etc/xdg/autostart entry; the vendored Hidden=true stub in
        # ~/.config/autostart masks it by default, exactly like upstream.
        system-config-printer
      ]
      ++ [
        # Qt Wayland platform plugins (portal integration, theming).
        qt5.qtwayland
        qt6.qtwayland
      ]
    );

  # Custom hyprland-uwsm.desktop matching the oracle's session launch.
  # nixpkgs programs.uwsm.waylandCompositors generates
  #   Exec=uwsm start -F -- <binPath>
  # which makes XDG_SESSION_DESKTOP=<bin basename> (start-hyprland) because
  # there is no -D DesktopNames flag and no DesktopNames= key. The oracle
  # (upstream Arch Omarchy) uses:
  #   Exec=uwsm start -e -D Hyprland hyprland.desktop
  # so DesktopNames come from hyprland.desktop (DesktopNames=Hyprland) and
  # XDG_SESSION_DESKTOP=Hyprland. That also keeps xdg-terminal-exec looking
  # for hyprland-xdg-terminals.list (not start-hyprland-xdg-terminals.list).
  hyprlandUwsmDesktop = pkgs.writeTextFile {
    name = "hyprland-uwsm";
    text = ''
      [Desktop Entry]
      Name=Hyprland (UWSM)
      Comment=Omarchy Quattro (uwsm-managed)
      Exec=${pkgs.uwsm}/bin/uwsm start -e -D Hyprland hyprland.desktop
      DesktopNames=Hyprland
      Type=Application
    '';
    destination = "/share/wayland-sessions/hyprland-uwsm.desktop";
    derivationArgs = {
      passthru.providedSessions = [ "hyprland-uwsm" ];
    };
  };

  # NixOS chromium ships as chromium-browser.desktop; Arch/upstream
  # finalize-user sets default-web-browser chromium.desktop. Alias the
  # Arch name so xdg-settings + omarchy-launch-browser match the oracle.
  chromiumDesktopAlias = pkgs.runCommand "chromium-desktop-alias" { } ''
    mkdir -p "$out/share/applications"
    cp ${pkgs.chromium}/share/applications/chromium-browser.desktop \
      "$out/share/applications/chromium.desktop"
  '';

  # Bare `gsettings` (unwrapped glib CLI) does not see Nix store schemas
  # unless GSETTINGS_SCHEMA_DIR points at the compiled schema dir.
  # wrapGAppsHook only fixes app wrappers; first-run scripts call the
  # system gsettings binary. Directory layout:
  #   $out/share/gsettings-schemas/<name>/glib-2.0/schemas/gschemas.compiled
  gsettingsSchemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
in
{
  options.omarchy = (import ../../config.nix { inherit lib; }).omarchyOptions;

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # (A) Vendored package + OMARCHY_PATH session variable.
      # We do NOT source upstream's default/bash/env-bootstrap: it carries
      # Arch/pacman dev-link logic (/etc/omarchy.conf) that has no NixOS
      # analogue. Instead OMARCHY_PATH is set through NixOS-native channels
      # (PAM session vars + uwsm env.d), which cover both login shells and
      # the uwsm-managed Hyprland session.
      (lib.mkIf (cfg.package != null) {
        environment.systemPackages = [ cfg.package ];

        # NixOS buildEnv only links subpaths listed in environment.pathsToLink.
        # The vendored tree lives entirely under share/omarchy, so without this
        # entry the package is accepted into the profile but its contents are
        # silently dropped and $OMARCHY_PATH would resolve to nothing. The extra
        # entries link the xdg-terminal-exec list + foot.desktop installed by the
        # derivation so xdg-terminal-exec can resolve the session default terminal.
        environment.pathsToLink = [
          "/share/omarchy"
          "/share/xdg-terminal-exec"
          "/share/applications"
        ];

        # OMARCHY_PATH + the omarchy-* bin scripts. Upstream expects the bin
        # scripts at /usr/bin/omarchy-* (Arch package layout); we vendor under
        # share/omarchy/bin instead, so prepend $OMARCHY_PATH/bin to PATH the
        # same way upstream's default/bash/env-bootstrap does in dev-link mode.
        # Without this every omarchy-* lookup exits 127 — Super+Enter, the
        # theme renderer, first-run hooks, quickshell's omarchy-shell calls all
        # break. mkBefore so omarchy's own omarchy-X wins over any same-named
        # system binary.
        #
        # BROWSER/TERMINAL mirror default/uwsm/default (upstream session env).
        # GSETTINGS_SCHEMA_DIR: see gsettingsSchemaDir above — first-run
        # gnome-theme.sh / gtk-primary-paste.sh call unwrapped gsettings.
        #
        # OMARCHY_USER_NAME/EMAIL are deliberately NOT here: NixOS renders
        # environment.sessionVariables into PAM's environment config, where a
        # literal @ is parsed as a PAM item expansion — pam_env logs
        # "Expandable variables must be wrapped in {}" and drops the value.
        # They reach the desktop session via uwsm env.d (below) and login
        # shells via /etc/profile (extraInit below that).
        environment.sessionVariables = {
          OMARCHY_PATH = "${cfg.package}/share/omarchy";
          PATH = [ "${cfg.package}/share/omarchy/bin" ];
          BROWSER = "omarchy-launch-browser";
          TERMINAL = "xdg-terminal-exec";
          # EDITOR/SUDO_EDITOR mirror default/bash/envs
          # (EDITOR="${EDITOR:-omarchy-launch-editor --inline}",
          # SUDO_EDITOR="$EDITOR"). mkDefault mirrors the `:-` soft-default
          # semantics — any user-set EDITOR wins. SUDO_EDITOR carries the
          # pam_env indirection ${EDITOR} verbatim into /etc/pam/environment
          # (the renderer quotes values and only remaps $HOME/$USER), where
          # pam_env expands it at login — alphabetically the EDITOR line
          # sorts first, so the expansion sees the effective value. This is
          # upstream's follows-EDITOR semantics; the module system itself
          # cannot self-reference inside one attrsOf option (recursion).
          EDITOR = lib.mkDefault "omarchy-launch-editor --inline";
          SUDO_EDITOR = lib.mkDefault "\${EDITOR}";
          # See gsettingsSchemaDir above — first-run gnome-theme.sh /
          # gtk-primary-paste.sh call unwrapped gsettings.
          GSETTINGS_SCHEMA_DIR = gsettingsSchemaDir;
        };

        # Login-shell route for OMARCHY_USER_NAME/EMAIL (feeds
        # install/user/git.sh + xcompose.sh via omarchy-finalize-user; the
        # upstream ISO sets them from the installer). /etc/profile parses
        # shell syntax, so a literal @ in the address is safe here.
        environment.extraInit = ''
          export OMARCHY_USER_NAME=${lib.escapeShellArg cfg.full_name}
          export OMARCHY_USER_EMAIL=${lib.escapeShellArg cfg.email_address}
        '';

        # systemd user manager route (deterministic): the manager itself
        # reads environment.d at startup, so OMARCHY_USER_NAME/EMAIL land in
        # the session env on every session path — SDDM, tty autologin, ssh —
        # regardless of how far uwsm's env.d chain gets (the tty autologin
        # path demonstrably does not deliver them; the uwsm file above stays
        # for upstream parity). fmt.envdLines applies environment.d(5)
        # quoting ($ -> $$, \ -> \\, " -> \") verified against systemd 260's
        # generator and omits empty values (the generator rejects empty
        # assignments); CR/LF is already rejected by the option type.
        environment.etc."environment.d/50-omarchy.conf".text =
          fmt.envdLines {
            OMARCHY_USER_NAME = cfg.full_name;
            OMARCHY_USER_EMAIL = cfg.email_address;
          }
          + "\n";

        # uwsm does not source /etc/profile.d; it scans uwsm/env.d/* under the
        # XDG config hierarchy (/etc/xdg on NixOS). Drop a fragment there so
        # the Hyprland session launched via uwsm sees OMARCHY_PATH + the bin
        # scripts on PATH too. OMARCHY_PATH/BROWSER/TERMINAL mirror
        # environment.sessionVariables above; OMARCHY_USER_NAME/EMAIL repeat
        # the environment.d values for upstream parity (default/uwsm/default
        # carries user identity in the session env too). EDITOR/SUDO_EDITOR
        # mirror default/bash/envs — env.d is shell, so the upstream `:-`
        # soft default works verbatim here.
        environment.etc."xdg/uwsm/env.d/10-omarchy".text = ''
          export OMARCHY_PATH="${cfg.package}/share/omarchy"
          export PATH="${cfg.package}/share/omarchy/bin:$PATH"
          export BROWSER=omarchy-launch-browser
          export TERMINAL=xdg-terminal-exec
          export EDITOR="''${EDITOR:-omarchy-launch-editor --inline}"
          export SUDO_EDITOR="$EDITOR"
          export OMARCHY_USER_NAME=${lib.escapeShellArg cfg.full_name}
          export OMARCHY_USER_EMAIL=${lib.escapeShellArg cfg.email_address}
          export GSETTINGS_SCHEMA_DIR=${lib.escapeShellArg gsettingsSchemaDir}'';

        # Path-adapted user units from pkgs/omarchy.nix ($out/lib/systemd/user).
        # generateUnits (type=user) symlinks systemd.packages' lib/systemd/user
        # into /etc/systemd/user. Enabling is separate — see block (H).
        systemd.packages = [ cfg.package ];
      })

      # (B) Runtime dependencies (filtered by omarchy.exclude_packages).
      {
        environment.systemPackages =
          runtimeDeps
          ++ (filterExcluded cfg.appPackages)
          ++ [
            xcursorDefaultAdwaita
            chromiumDesktopAlias
          ];

        # Font discovery for the runtime fonts above. (Mirrors the names in
        # runtimeDeps; kept explicit here because environment.systemPackages
        # alone does not populate the font cache.) cfg.package contributes the
        # omarchy icon font (share/fonts/omarchy/omarchy.ttf, menu glyphs);
        # liberation_ttf is required by the upstream fontconfig aliases below.
        fonts.packages = [
          pkgs.noto-fonts
          pkgs.noto-fonts-cjk-sans
          pkgs.noto-fonts-color-emoji
          pkgs.nerd-fonts.jetbrains-mono
          pkgs.font-awesome
          pkgs.ia-writer-quattro
          pkgs.liberation_ttf
        ]
        ++ lib.optional (cfg.package != null) cfg.package;
      }

      # (B0) Unfree whitelist + scoped insecure permit for the default app set
      # and menu-managed packages. The default set ships obsidian (upstream
      # parity), which is unfree — whitelist exactly it so a consumer on a
      # default nixpkgs config builds without touching nixpkgs.config. Menu
      # installs extend the whitelist with catalog `unfreeNames` (literal
      # getName strings, including hidden deps like steam-unwrapped) and
      # `insecureNames` (e.g. openssl-1.1.1w for Sublime, electron for
      # Bitwarden) only when selected. nixpkgs combines allowUnfree /
      # allowUnfreePackages / allowUnfreePredicate with OR, and a consumer's
      # own plain assignment wins over this mkDefault — so this never narrows
      # what the consumer themselves allowed.
      #
      # Only when NixOS owns the nixpkgs instance: with an externally created
      # pkgs (nixpkgs.pkgs set, e.g. this flake's demo configs via pkgsFor)
      # setting nixpkgs.config trips the "externally created instance"
      # assertion — and is unnecessary there, since the external instance
      # already carries its own unfree policy. Note the discriminator is
      # options.nixpkgs.pkgs.isDefined (the same one the NixOS assertion
      # uses), NOT config.nixpkgs.pkgs == null: the nixpkgs module writes its
      # own constructed instance back into config.nixpkgs.pkgs, so that value
      # is non-null even when NixOS built it.
      (lib.mkIf (!options.nixpkgs.pkgs.isDefined) {
        nixpkgs.config.allowUnfreePredicate = lib.mkDefault (
          pkg: builtins.elem (lib.getName pkg) ([ "obsidian" ] ++ managedUnfreeNames)
        );
        # Scoped opt-in: only the insecure deps of packages the consumer
        # actually selected (Sublime → openssl-1.1.1w, Bitwarden → electron).
        # List option merges with any consumer-supplied entries.
        nixpkgs.config.permittedInsecurePackages = managedInsecureNames;
        # Scoped opt-in for pkgs newer nixpkgs marks broken via the problems
        # mechanism (Sublime → sublimetext4.broken). "warn" keeps the warning
        # visible while allowing evaluation. Empty unless selected; the option
        # exists on both supported pins (26.05 and 26.11). Catalog keys are
        # flat "pname.problem" strings — nest them for the option.
        nixpkgs.config.problems.handlers = lib.foldl' lib.recursiveUpdate { } (
          map (
            h:
            let
              m = builtins.match "([^.]+)\\.(.+)" h;
            in
            lib.setAttrByPath [ (builtins.head m) (builtins.elemAt m 1) ] "warn"
          ) managedProblemHandlers
        );
      })

      # (B0b) Menu-managed packages: fold omarchy-packages.json into the
      # system. packages -> systemPackages; features -> managedFeatureDefs
      # blocks (Task 5). Unknown names throw an eval error naming the file —
      # in the normal flow omarchy-nix-add validates before writing.
      #
      # IMPORTANT: managedFeatures is config-dependent (it reads
      # cfg.managedPackagesFile). Referencing it at the mkMerge LIST level
      # would force it during the module system's property-pushing phase,
      # before the config fixed point exists, causing infinite recursion.
      # Instead we iterate over managedFeatureDefs keys (stable, defined in
      # the let) and gate each with mkIf — conditions are thunks that are
      # only evaluated after config is built.
      #
      # The unknown-feature throw is folded into environment.systemPackages
      # (always forced by the toplevel) so it actually discharges. An mkIf
      # with a throw condition and empty {} content would be dead code —
      # the module system never forces conditions of mkIf blocks whose
      # content produces no option paths.
      (lib.mkIf (cfg.managedPackagesFile != null) (
        lib.mkMerge (
          [
            {
              environment.systemPackages =
                let
                  unknown = builtins.filter (f: !(managedFeatureDefs ? ${f})) managedFeatures;
                in
                if unknown != [ ] then
                  throw "${toString cfg.managedPackagesFile}: unknown feature '${builtins.head unknown}' (known: ${builtins.concatStringsSep ", " (builtins.attrNames managedFeatureDefs)})"
                else
                  map (
                    n: pkgs.${n} or (throw "${toString cfg.managedPackagesFile}: unknown nixpkgs attribute '${n}'")
                  ) managedPkgs;
            }
          ]
          ++ lib.attrValues (
            lib.mapAttrs (name: config: lib.mkIf (builtins.elem name managedFeatures) config) managedFeatureDefs
          )
        )
      ))

      # (B1) Upstream fontconfig aliases (50-omarchy.conf): Liberation Sans as
      # default sans/system-ui, JetBrainsMono Nerd Font as default monospace,
      # Noto Naskh Arabic for Arabic. Shipped by upstream at
      # /etc/fonts/conf.d/50-omarchy.conf. /etc/fonts is owned by the NixOS
      # fonts module, so the conf goes in via fonts.fontconfig.confPackages
      # (a package carrying etc/fonts/conf.d), not environment.etc.
      (lib.mkIf (cfg.package != null) {
        fonts.fontconfig.confPackages = [
          (pkgs.runCommand "omarchy-fontconfig-conf" { } ''
            mkdir -p "$out/etc/fonts/conf.d"
            ln -s "${cfg.package}/share/omarchy/default/fontconfig/conf.avail/50-omarchy.conf" \
              "$out/etc/fonts/conf.d/50-omarchy.conf"
          '')
        ];
      })

      # (B2) Upstream parity services. All mkDefault so a consumer can override
      # any of them (e.g. disable docker on a headless host). These mirror the
      # services upstream omarchy enables on a default Arch install.
      {
        services.avahi = {
          enable = lib.mkDefault true;
          nssmdns4 = lib.mkDefault true;
        };
        services.power-profiles-daemon.enable = lib.mkDefault true;
        services.printing = {
          enable = lib.mkDefault true;
          # cups-browsed: remote printer discovery. The seeded autostart
          # print-applet.desktop expects a running CUPS. nixpkgs 26.05 exposes
          # this as services.printing.browsed (not .cups-browsed).
          browsed.enable = lib.mkDefault true;
        };
        virtualisation.docker.enable = lib.mkDefault true;
        # gnome-keyring: upstream ships it; the old "out of scope" note in
        # AGENTS.md is rescinded.
        services.gnome.gnome-keyring.enable = lib.mkDefault true;
        services.hardware.bolt.enable = lib.mkDefault true;
        # gvfs daemon: Nautilus trash/mount support (the gvfs *package* is in
        # runtimeDeps; the *service* wires the daemons).
        services.gvfs.enable = lib.mkDefault true;
        # fwupd: keeps omarchy-update-firmware (fwupdmgr) working. Upstream
        # installs the package via pacman; we enable the service as mkDefault.
        services.fwupd.enable = lib.mkDefault true;

        # ydotoold system daemon: voxtype's [output] mode = "type" types the
        # transcription via ydotool (upstream default/voxtype/config.toml).
        # The daemon socket is group-owned; the login user must be in the
        # `ydotool` group (consumer's users.users.<name>.extraGroups).
        programs.ydotool.enable = lib.mkDefault true;

        # Qt theming parity: upstream's vendored default/hypr/envs.lua sets
        # QT_QPA_PLATFORMTHEME=gtk3 in the session (the kvantum style +
        # QT_STYLE_OVERRIDE were dropped upstream together with the kvantum
        # packages, migrations/1785351479.sh). qt.enable keeps QStyle plugins
        # from systemPackages discoverable (profile-relative
        # QT_PLUGIN_PATH/QML2_IMPORT_PATH); no qt.style is set — Qt follows
        # the gtk3 platform theme like upstream.
        qt.enable = lib.mkDefault true;

        # gpu-screen-recorder (upstream parity): bin/omarchy-capture-screenrecording
        # and the bar indicator (shell/plugins/bar/indicators/ScreenRecording.qml)
        # shell out to it. The nixpkgs module installs the package AND the
        # setcap security wrapper for gsr-kms-server — without the wrapper the
        # KMS backend dies with "pkexec must be setuid root" and recording
        # never starts (verified on real AMD hardware).
        programs.gpu-screen-recorder.enable = lib.mkDefault true;

        # UPower: the shell's battery service (services/battery — low-battery
        # warning + AC/battery power-profile switching) and the power panel's
        # battery icon/percentage read Quickshell.Services.UPower over DBus.
        # NixOS does not enable the daemon by default; without it every
        # battery read silently returns "not present" (wireplumber logs the
        # same gap). Arch enables upower transitively on a desktop install.
        services.upower.enable = lib.mkDefault true;

        # udiskie automount user service (upstream parity). Package is in
        # runtimeDeps; this starts it under the graphical session.
        systemd.user.services.udiskie = {
          description = "udiskie automounter";
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.udiskie}/bin/udiskie";
            Restart = "on-failure";
          };
        };

        # zram swap (upstream parity): default/systemd/zram-generator.conf.d/
        # 90-omarchy.conf — full-RAM zram device, zstd (~3:1, so ~1/3 RAM in
        # practice), swap-priority 100 (above the pri=0 disk swapfile from
        # omarchy-hibernation-setup). NixOS's zramSwap drives the same
        # zram-generator under the hood; memoryPercent 100 renders as
        # `zram-size = 100 / 100 * ram`, equivalent to upstream's `ram`.
        zramSwap.enable = lib.mkDefault true;
        zramSwap.memoryPercent = lib.mkDefault 100;
        zramSwap.algorithm = lib.mkDefault "zstd";
        zramSwap.priority = lib.mkDefault 100;

        # zswap off (upstream etc/tmpfiles.d/omarchy-zswap.conf): in front of
        # swap-on-zram it only double-compresses pages and breaks zramctl
        # accounting. w! = boot-only, so a manual flip sticks until reboot.
        # Upstream's zram migration (drop archinstall's leftover
        # /etc/systemd/zram-generator.conf) is a no-op on NixOS — no such file.
        systemd.tmpfiles.rules = [
          "w! /sys/module/zswap/parameters/enabled - - - - N"
        ];

        # Cross-arch binfmt: upstream installs
        # qemu-user-static-binfmt unconditionally; here it is opt-in via
        # omarchy.binfmtEmulatedSystems (default []). An empty list merges to
        # a no-op; a consumer's own boot.binfmt.emulatedSystems entries merge
        # with this list (plain list concatenation, no override needed).
        boot.binfmt.emulatedSystems = cfg.binfmtEmulatedSystems;

        # --- Upstream /etc defaults (shipped under upstream's Arch etc/ tree) ---

        # Mask NetworkManager-wait-online (upstream migration 1784568652):
        # graphical.target was gated on network-online.target because
        # cups-browsed (enabled above) orders after it, so the desktop waited
        # for DHCP/Wi-Fi association at boot. Declaring the unit with
        # enable = false makes nixpkgs link it to /dev/null (a systemd mask).
        systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

        # logind inhibit delay (upstream etc/systemd/logind.conf.d/
        # 20-inhibit-delay.conf): omarchy-sleep-lock holds a delay inhibitor
        # so the session is locked before suspend; the 5s default expires
        # while Quickshell secures the session on lid close. Costs nothing
        # when locking is healthy (the inhibitor releases in under a second).
        services.logind.settings.Login.InhibitDelayMaxSec = lib.mkDefault 15;

        # Wi-Fi powersave off (upstream etc/NetworkManager/conf.d/
        # omarchy-wifi-powersave.conf: [connection] wifi.powersave = 2) —
        # powersave trades 20-300ms latency spikes for a fraction of a watt,
        # and Intel BE200/BE211 firmware drops the link outright. Renders as
        # wifi.powersave=2 under [connection] in NetworkManager.conf.
        networking.networkmanager.wifi.powersave = lib.mkDefault false;
      }

      # (C) SSH must stay reachable.
      # Applying omarchy via `nixos-rebuild switch --flake` rebuilds the whole
      # system activation from the consumer's config. If that config does not
      # enable sshd, the switch silently removes the running sshd and the box
      # becomes an unrecoverable lockout for a remote operator (no serial
      # console, no flakes in the old generation to roll forward from). mkDefault
      # so a consumer who genuinely wants no SSH can still override to false.
      #
      # Keys-only by default: password and keyboard-interactive logins are
      # off, so a box with a weak or publicly documented initial password is
      # not SSH-able over the LAN. To allow password auth explicitly:
      #   services.openssh.settings.PasswordAuthentication = true;
      {
        services.openssh.enable = lib.mkDefault true;
        services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
        services.openssh.settings.KbdInteractiveAuthentication = lib.mkDefault false;
      }

      # (C2) dconf backend for gsettings (first-run gnome-theme.sh +
      # gtk-primary-paste.sh write org.gnome.desktop.interface keys). Without
      # this, gsettings exits non-zero and those first-run steps fail.
      { programs.dconf.enable = lib.mkDefault true; }

      # (D) Hyprland (>= 0.56, Lua config) via uwsm + default SDDM.
      # The flake wrapper injects the Hyprland package from the hyprland
      # input as the default; here we just enable the NixOS machinery.
      {
        # Hyprland Cachix — the flake package is NOT built by Hydra, so
        # without this every consumer rebuilds Hyprland + its deps (mesa,
        # ffmpeg, aquamarine, ...) from source. That is a multi-hour build
        # on a fresh machine and can OOM a small VM. Register the upstream
        # Cachix automatically so the binary cache is used. Per Hyprland
        # docs this must be in place BEFORE the first build that pulls the
        # flake package; since the flake wrapper injects the package and we
        # enable it here, both land in the same evaluation.
        nix.settings = {
          substituters = lib.mkBefore [ "https://hyprland.cachix.org" ];
          trusted-substituters = [ "https://hyprland.cachix.org" ];
          trusted-public-keys = [
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          ];
          # Required so non-root users (the one running nixos-rebuild) can
          # use the substituter. @wheel covers sudoers.
          trusted-users = [
            "root"
            "@wheel"
          ];
        };

        programs.hyprland = {
          enable = true;
          xwayland.enable = true;
          # uwsm-managed session: improved systemd integration (graphical
          # session targets, env preloading). Recommended upstream path and
          # matches the live reference box (hyprland-uwsm.desktop).
          # withUWSM enables programs.uwsm but does NOT register a session
          # entry — we ship our own below for oracle desktop-name parity.
          withUWSM = true;
        };

        # Ship a custom hyprland-uwsm.desktop instead of
        # programs.uwsm.waylandCompositors. The nixpkgs helper generates
        # `uwsm start -F -- <binPath>` with no -D DesktopNames, which leaves
        # XDG_SESSION_DESKTOP=start-hyprland. The upstream reference install
        # and upstream intent: `uwsm start -e -D Hyprland hyprland.desktop`, so
        # XDG_SESSION_DESKTOP=Hyprland. hyprland.desktop itself comes from
        # programs.hyprland.package (Exec=start-hyprland, DesktopNames=Hyprland)
        # — that still covers the start-hyprland session-entry requirement.
        # providedSessions = ["hyprland-uwsm"] keeps defaultSession working.
        environment.systemPackages = [ hyprlandUwsmDesktop ];
        services.displayManager.sessionPackages = [ hyprlandUwsmDesktop ];

        # Default SDDM (omarchy applies its login theme + Hyprland greeter
        # in the (D) block below; this just enables the display manager).
        # mkDefault so a consumer can swap in another display manager.
        services.displayManager.sddm.enable = lib.mkDefault true;

        # PipeWire needs the daemon enabled to actually run; the package alone
        # is not enough. Keep this here so audio works out of the box.
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };

        # NetworkManager + Bluetooth daemons. nmcli/bluez-utils are useless
        # without the running daemons; enabling them here makes the desktop
        # functional out of the box. Both are mkDefault so a consumer on a
        # headless/special-networking host can disable them.
        networking.networkmanager.enable = lib.mkDefault true;
        hardware.bluetooth.enable = lib.mkDefault true;

        # External monitor brightness over DDC/CI (omarchy-brightness-display-ddc).
        # Loads i2c-dev and creates the i2c group; the user still needs to be
        # in that group (consumer's users.users.<name>.extraGroups, same model
        # as ydotool above).
        hardware.i2c.enable = lib.mkDefault true;

        # systemd-oomd: let the OOM daemon kill a runaway app instead of
        # losing the whole session (upstream install/config/enable-services.sh).
        # The vendored drop-ins pin the pressure thresholds; the app.slice
        # drop-in (kill candidates = user apps only, never the compositor)
        # rides along systemd.packages from the omarchy package itself.
        systemd.oomd.enable = lib.mkDefault true;
        environment.etc."systemd/oomd.conf.d/10-omarchy.conf".source =
          "${cfg.package}/share/omarchy/etc/systemd/oomd.conf.d/10-omarchy.conf";
      }

      # (E) Plymouth boot-splash theme.
      # The vendored omarchy theme package installs to
      # $out/share/plymouth/themes/omarchy/ with the .plymouth config's
      # hardcoded /usr paths rewritten to the nix store (handled by the
      # derivation). boot.plymouth.theme + themePackages wire NixOS to use it.
      (lib.mkIf (cfg.plymouth.enable && cfg.plymouthPackage != null) {
        boot.plymouth = {
          enable = true;
          theme = "omarchy";
          themePackages = [ cfg.plymouthPackage ];
        };
      })

      # (F) SDDM login theme + Hyprland greeter config.
      # The theme package installs to $out/share/sddm/themes/omarchy/ (SDDM
      # discovers it via $XDG_DATA_DIRS) and ships the greeter Hyprland Lua
      # config at $out/share/sddm/hyprland.lua. We set the theme name and
      # point the Wayland greeter CompositorCommand at Hyprland with that
      # config, matching the live reference box (start-hyprland -- --config
      # /usr/share/sddm/hyprland.lua).
      (lib.mkIf (cfg.sddm.theme && cfg.sddmPackage != null) {
        services.displayManager.sddm.theme = "omarchy";
        environment.systemPackages = [ cfg.sddmPackage ];

        # SDDM needs the theme on its data path; ensure /share/sddm is linked.
        environment.pathsToLink = [ "/share/sddm" ];

        # Run the Wayland greeter under Hyprland using the vendored minimal
        # config. CompositorCommand is otherwise internal-only (defaults to
        # weston/kwin), so we set it explicitly via sddm.settings. The greeter
        # config disables the Hyprland logo/splash and animations.
        services.displayManager.sddm.wayland.enable = lib.mkDefault true;
        services.displayManager.sddm.settings.Wayland.CompositorCommand =
          lib.mkForce "Hyprland --config ${cfg.sddmPackage}/share/sddm/hyprland.lua";
      })

      # (G) Optional SDDM autologin (LUKS-aware single-password UX).
      # When omarchy.autologin.user is set, configure the NixOS display-manager
      # autoLogin options — NOT sddm.settings.AutoLogin (which the SDDM module
      # ignores; the [AutoLogin] section is emitted only from
      # services.displayManager.autoLogin.{enable,user}). Land autologin in the
      # uwsm-managed Hyprland session via defaultSession so it does not fall
      # through to the bare hyprland.desktop entry. Typical use: an encrypted
      # (LUKS) install where the user already unlocked the disk at boot, so a
      # second SDDM prompt is redundant.
      (lib.mkIf (cfg.autologin.user != null) {
        services.displayManager.autoLogin = {
          enable = true;
          user = cfg.autologin.user;
        };
        services.displayManager.defaultSession = lib.mkDefault "hyprland-uwsm";
        services.displayManager.sddm.autoLogin.relogin = true;
      })

      # (H) Enable the path-adapted systemd user units declaratively.
      # Upstream's install/user/first-run/enable-user-units.sh runs
      # `systemctl --user enable --now` for five of the seven units; NixOS
      # ignores package-unit [Install] sections, so wantedBy here creates the
      # .wants/ links. Unit bodies come from cfg.package via systemd.packages
      # (block A) — setting wantedBy alone becomes a drop-in, not a rewrite.
      # Skipped: omarchy-speaker-tuning (enabled by omarchy-audio-tuning when
      # a hardware match exists), omarchy-tailscale-receive (no tailscale in
      # runtimeDeps; unit is still shipped for consumers who add it).
      (lib.mkIf (cfg.package != null) {
        systemd.user.services = {
          bt-agent.wantedBy = [ "graphical-session.target" ];
          omarchy-fcitx5.wantedBy = [ "graphical-session.target" ];
          omarchy-migrate-notify.wantedBy = [ "graphical-session.target" ];
          # sleep-lock script execs bare `bash`, `systemd-inhibit`, and
          # `dbus-monitor`. User-unit PATH is sparse (no /run/current-system
          # unless hyprland setPath is on), so put them on the unit PATH
          # rather than rewriting the vendored script body.
          omarchy-sleep-lock = {
            wantedBy = [ "graphical-session.target" ];
            path = with pkgs; [
              bash
              systemd
              dbus
            ];
          };
          omarchy-recover-internal-monitor.wantedBy = [ "graphical-session-pre.target" ];
        };
      })

      # (I) System timezone from omarchy.timezone. mkDefault so a consumer's
      # own time.timeZone (e.g. from hardware-configuration.nix) wins.
      {
        time.timeZone = lib.mkDefault cfg.timezone;
      }

      # (J) omarchy.terminal -> xdg-terminal-exec preference list. The
      # vendored fallback (share/xdg-terminal-exec/hyprland-xdg-terminals.list,
      # foot only) lives in the XDG data dirs; /etc/xdg is XDG_CONFIG_DIRS,
      # which xdg-terminal-exec searches first — so this list wins for the
      # Hyprland session. foot stays as the fallback entry; an uninstalled
      # choice degrades to foot instead of breaking Super+Enter.
      (lib.mkIf (cfg.package != null) {
        environment.etc."xdg/hyprland-xdg-terminals.list".text = ''
          ${cfg.terminal}.desktop
          foot.desktop
        '';
      })

      # (K) Lock-screen PAM services. The Quickshell lock plugin
      # authenticates through PAM configs named omarchy-lock-password and
      # omarchy-lock-fingerprint (Service.qml PamContext). Upstream writes
      # them imperatively from omarchy-setup-lock; here they are declared
      # with the verbatim upstream auth stack. Two deliberate deviations:
      # the account phase replaces Arch's `include system-local-login` with
      # pam_unix (NixOS ships no system-local-login service), and the
      # faillock tally writes degrade silently when /var/run/faillock is
      # missing — exactly as they do for user-context PAM stacks upstream.
      # Consumers override the policy with mkForce on the same attrpaths.
      {
        security.pam.services.omarchy-lock-password.text = ''
          #%PAM-1.0
          auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
          -auth      [success=2 default=ignore]  pam_systemd_home.so
          auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
          auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
          auth       optional                    pam_permit.so
          auth       required                    pam_env.so
          auth       required                    pam_faillock.so authsucc
          account    required                    pam_unix.so
        '';
      }

      # (L) Fingerprint lock auth — opt-in only (omarchy.fingerprint.enable),
      # mirroring upstream where the service exists only after enrollment.
      (lib.mkIf cfg.fingerprint.enable {
        services.fprintd.enable = true;
        security.pam.services.omarchy-lock-fingerprint.text = ''
          #%PAM-1.0
          auth       required                    pam_fprintd.so
          account    required                    pam_unix.so
        '';
      })

      # (M) Opt-in Fish shell profile. Installs fish + the
      # vendored omarchy-fish profile (share/fish/vendor_*). nixpkgs' fish
      # module links vendor_{conf,completions,functions}.d into the system
      # profile by default (programs.fish.vendor.*.enable = true), so no
      # extra pathsToLink is needed. The login shell stays a per-account
      # consumer setting (users.users.<name>.shell = pkgs.fish) — the module
      # must not guess which account to mutate.
      (lib.mkIf cfg.fish.enable {
        assertions = [
          {
            assertion = cfg.fish.package != null;
            message = "omarchy.fish.enable requires omarchy.fish.package to be set — use the flake's nixosModules.default (which injects it) or point it at an omarchy-fish package.";
          }
        ];
        programs.fish.enable = true;
        environment.systemPackages = [ cfg.fish.package ];
      })
    ]
  );
}
