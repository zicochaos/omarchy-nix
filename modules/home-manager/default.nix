# Home-Manager module: seed the Omarchy (Quattro) per-user config.
#
# Wires the Hyprland Lua entry point (~/.config/hypr/hyprland.lua) that
# dispatches into the vendored upstream tree, plus the user-editable stub
# files the entry point requires(), plus the default-theme symlink in
# ~/.local/state. Designed to compose with the NixOS module (Stage 3):
# when osConfig.omarchy is present, the same options drive both layers.
#
# Seeding strategy:
# the upstream omarchy UX assumes users edit ~/.config after install
# (Setup menu, omarchy-refresh-config, omarchy-theme-set, …). Per the
# ownership doctrine nothing under $HOME that upstream tooling touches
# may be a store symlink. We split the seed into classes:
#   1. User-editable stubs -> activation script with [ ! -e ] / legacy
#      store-symlink guard (pattern from HM programs/t3code.nix + gpg.nix)
#   2. Vendored defaults -> NOT copied; bootstrap.lua loads them from
#      $OMARCHY_PATH via package.path
#
# NOTE on osConfig mirroring: the common idiom `omarchy = osConfig.omarchy`
# inside `mkIf cfg.enable` creates an evaluation cycle (cfg.enable <- mirror
# <- config.omarchy <- cfg.enable). Instead we read the effective values
# directly from osConfig with a fallback to the HM-local option, computed
# inside the config block (lazily) so they never gate the option that gates
# them. The mirror, when present, uses mkDefault so a standalone HM user's
# explicit values win.
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:

let
  # The vendored upstream config/ tree lives in the (read-only) store and is
  # the source of truth for the user-editable stubs. Reading from it (rather
  # than copying files into this repo) honors "vendor, don't rewrite".
  upstreamConfig = pkg: "${pkg}/share/omarchy/config";
  omarchyPathOf = pkg: "${pkg}/share/omarchy";

  # Seed a user-editable file only if it does not already exist (or is a
  # legacy store symlink from older module versions that used xdg.configFile).
  # The first home-manager switch copies the upstream template; later switches
  # never touch a real file, so user edits survive. `cp -a` (not `ln -s`)
  # produces a regular file the user can edit. chmod u+w makes it actually
  # writable — cp -a preserves the store's read-only mode, but upstream
  # runtime tooling (omarchy-hyprland-monitor-scaling) writes to monitors.lua
  # via sed -i, and users need to edit all stubs.
  # seedFileFrom takes a path relative to $HOME (for seeds that live outside
  # ~/.config, e.g. the skel parity files under ~/.local/share and
  # ~/.local/state); seedStubFrom is the ~/.config convenience wrapper.
  seedFileFrom = source: target: ''
    omarchy_seed_target="$HOME/${target}"
    if [ ! -e "$omarchy_seed_target" ] || { [ -L "$omarchy_seed_target" ] && [[ "$(readlink -f "$omarchy_seed_target")" == /nix/store/* ]]; }; then
      mkdir -p "$(dirname "$omarchy_seed_target")"
      rm -f "$omarchy_seed_target"
      cp -a "${source}" "$omarchy_seed_target"
      chmod u+w "$omarchy_seed_target"
    fi'';

  seedStubFrom = source: target: seedFileFrom source ".config/${target}";

  # Convenience: seed from the vendored upstream config tree by relative path.
  seedStub = pkg: relPath: seedStubFrom "${upstreamConfig pkg}/${relPath}" relPath;

  # Generate ~/.config/hypr/monitors.lua from omarchy.scale + omarchy.monitors.
  # Upstream's template hardcodes GDK_SCALE=2; we derive both knobs so a 1x
  # display gets sane defaults. Per-monitor entries from omarchy.monitors are
  # emitted as additional hl.monitor({}) calls after the catch-all, in the same
  # Lua table shape upstream uses. The catch-all (output = "") and the
  # omarchy_gdk_scale / omarchy_monitor_scale locals are always present because
  # upstream runtime tooling (omarchy-hyprland-monitor-scaling) greps for them
  # to persist user-initiated scaling changes to this file at runtime. This is
  # the only parametrized stub — every other user file is copied verbatim.
  # Validation and Lua escaping live in modules/lib/omarchy-formats.nix:
  # a malformed monitor entry fails evaluation, a quote or
  # newline in a name can no longer break out of the Lua string literal.
  fmt = import ../lib/omarchy-formats.nix { inherit lib; };
  monitorsLua =
    scale: monitors:
    pkgs.writeText "omarchy-monitors.lua" (fmt.monitorsLuaText { inherit scale monitors; });
  # Port-side addition (upstream ships no wayland.conf): fcitx5's wayland
  # module runs selfDiagnose() 10s into every session and, when
  # allowOverrideXKB is on (the upstream default true) and the input-method
  # groups use more than one layout, notifies "Sending keyboard layout
  # configuration to wayland compositor from Fcitx is not yet supported on
  # current desktop". The override only works on KDE/GNOME — Hyprland has no
  # such protocol — so flipping it loses nothing and silences the benign
  # diagnose. Mirrors upstream's own xcb.conf, which ships the same option
  # set to False for the X11 path.
  fcitx5WaylandConf = pkgs.writeText "fcitx5-wayland.conf" ''
    Allow Overriding System XKB Settings=False
  '';

in
{
  options.omarchy = (import ../../config.nix { inherit lib; }).omarchyOptions;

  config =
    let
      cfg = config.omarchy;
      # Effective values: prefer osConfig (NixOS case), fall back to the
      # HM-local option (standalone case). Read here, lazily, rather than at
      # module top so the osConfig mirror does not cycle with mkIf cfg.enable.
      effPkg = (osConfig.omarchy or cfg).package;
      effScale = (osConfig.omarchy or cfg).scale;
      effMonitors = (osConfig.omarchy or cfg).monitors;
      effTheme = (osConfig.omarchy or cfg).theme;
      effNvimPkg = (osConfig.omarchy or cfg).nvimPackage or null;
      effSkill = "${omarchyPathOf effPkg}/default/omarchy-skill";
    in
    lib.mkIf cfg.enable (
      lib.mkIf (effPkg != null) {
        # NOTE: we deliberately do NOT mirror `omarchy = osConfig.omarchy`
        # here. That idiom would assign omarchy.enable from osConfig and form
        # an evaluation cycle with the `mkIf cfg.enable` gate above. Instead
        # effPkg/effScale/effTheme read directly from osConfig.omarchy with a
        # fallback to the HM-local option; omarchy.enable stays an HM-local
        # switch the consumer sets explicitly.

        # --- Class 0: agent skill links (managed on every activation) ---
        # Upstream finalize-user creates these four links once. On Arch their
        # target is the stable /usr/share path, but on NixOS OMARCHY_PATH is a
        # generation-specific store path. A one-shot link therefore keeps the
        # old package after an update and eventually becomes dangling after
        # garbage collection. Home Manager owns the same upstream paths and
        # refreshes them to the active package at every switch. `force` also
        # adopts links made by finalize-user before this module was deployed.
        home.file =
          lib.genAttrs
            [
              ".agents/skills/omarchy"
              ".claude/skills/omarchy"
              ".codex/skills/omarchy"
              ".pi/agent/skills/omarchy"
            ]
            (_: {
              source = effSkill;
              force = true;
            });

        # --- Class 1: user-editable stubs (seeded once) ---
        # Every file below is copied verbatim from the vendored upstream
        # config/ tree the first time home-manager switches, and never
        # touched again — so user edits survive subsequent switches
        # (pattern from HM programs/t3code.nix + programs/gpg.nix).
        # Legacy store symlinks (from older module versions that used
        # xdg.configFile) are replaced on the next switch.
        #
        # hyprland.lua and .luarc.json are included here: upstream UX lets
        # users edit them (Setup menu → edit config) and
        # omarchy-refresh-config must be able to overwrite them. They must
        # not be immutable store symlinks.
        #
        # monitors.lua is the one exception: it is generated from
        # omarchy.scale + omarchy.monitors (upstream hardcodes GDK_SCALE=2).
        #
        # Grouped by upstream config/ subdir so the rationale stays local.
        home.activation.omarchySeedUserConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          # --- hypr/ : entry point + modules hyprland.lua requires() + the
          # non-Lua Hyprland config files (greeter, portal, night light).
          ${seedStub effPkg "hypr/hyprland.lua"}
          ${seedStub effPkg "hypr/.luarc.json"}
          ${seedStub effPkg "hypr/input.lua"}
          ${seedStub effPkg "hypr/bindings.lua"}
          ${seedStub effPkg "hypr/looknfeel.lua"}
          ${seedStub effPkg "hypr/autostart.lua"}
          ${seedStub effPkg "hypr/hyprsunset.conf"}
          ${seedStub effPkg "hypr/xdph.conf"}
          ${seedStubFrom "${monitorsLua effScale effMonitors}" "hypr/monitors.lua"}

          # --- omarchy/ : the Quattro shell layout + hook drop-in dirs
          # (sample scripts the user can enable by renaming .sample) +
          # the menu launcher config + the themed template.
          ${seedStub effPkg "omarchy/shell.json"}
          ${seedStub effPkg "omarchy/extensions/omarchy-menu.jsonc"}
          ${seedStub effPkg "omarchy/themed/alacritty.toml.tpl.sample"}
          ${seedStub effPkg "omarchy/hooks/battery-low.d/play-warning-sound.sample"}
          ${seedStub effPkg "omarchy/hooks/font-set.d/show-font-notification.sample"}
          ${seedStub effPkg "omarchy/hooks/post-boot.d/weather.sample"}
          ${seedStub effPkg "omarchy/hooks/post-update.d/show-update-notification.sample"}
          ${seedStub effPkg "omarchy/hooks/pre-refresh-pacman.d/add-custom-repo.sample"}
          ${seedStub effPkg "omarchy/hooks/theme-set.d/show-theme-notification.sample"}

          # --- terminals : the four terminals Quattro ships configs for.
          ${seedStub effPkg "ghostty/config"}
          ${seedStub effPkg "foot/foot.ini"}
          ${seedStub effPkg "alacritty/alacritty.toml"}
          ${seedStub effPkg "kitty/kitty.conf"}

          # --- dev tools
          ${seedStub effPkg "git/config"}
          ${seedStub effPkg "tmux/tmux.conf"}
          ${seedStub effPkg "lazygit/config.yml"}
          ${seedStub effPkg "btop/btop.conf"}
          ${seedStub effPkg "starship.toml"}
          ${seedStub effPkg "opencode/opencode.json"}

          # --- input / media
          ${seedStub effPkg "fcitx5/conf/clipboard.conf"}
          ${seedStub effPkg "fcitx5/conf/xcb.conf"}
          ${seedStubFrom fcitx5WaylandConf "fcitx5/conf/wayland.conf"}
          ${seedStub effPkg "imv/config"}
          ${seedStub effPkg "wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"}

          # --- apps
          ${seedStub effPkg "chromium-flags.conf"}
          ${seedStub effPkg "chromium/Default/Preferences"}
          ${seedStub effPkg "obsidian/user-flags.conf"}
          ${seedStub effPkg "xournalpp/settings.xml"}
          ${seedStub effPkg "hyprland-preview-share-picker/config.yaml"}

          # --- autostart : XDG autostart desktop entries (launched by
          # the desktop environment on session start).
          ${seedStub effPkg "autostart/limine-snapper-notify.desktop"}
          ${seedStub effPkg "autostart/org.fcitx.Fcitx5.desktop"}
          ${seedStub effPkg "autostart/print-applet.desktop"}

          # --- branding (ISO /etc/skel parity): the about + screensaver
          # ASCII art. omarchy-screensaver loops "File not found" without
          # screensaver.txt; omarchy-branding-* rewrites these at runtime.
          ${seedStubFrom "${omarchyPathOf effPkg}/icon.txt" "omarchy/branding/about.txt"}
          ${seedStubFrom "${omarchyPathOf effPkg}/logo.txt" "omarchy/branding/screensaver.txt"}

          # --- skel parity outside ~/.config: nautilus-python extensions
          # (right-click LocalSend / transcode actions) and the tensaku
          # state file the app expects on first run.
          ${seedFileFrom "${omarchyPathOf effPkg}/default/nautilus-python/extensions/localsend.py" ".local/share/nautilus-python/extensions/localsend.py"}
          ${seedFileFrom "${omarchyPathOf effPkg}/default/nautilus-python/extensions/transcode.py" ".local/share/nautilus-python/extensions/transcode.py"}
          ${seedFileFrom "${omarchyPathOf effPkg}/default/tensaku/state.toml" ".local/state/tensaku/state.toml"}

          # --- voxtype dictation config. Upstream copies this in
          # omarchy-voxtype-install; the package is shipped declaratively
          # (runtimeDeps), so seed the default config up front — the install
          # script's later cp is then a no-op over identical content.
          ${seedStubFrom "${omarchyPathOf effPkg}/default/voxtype/config.toml" "voxtype/config.toml"}
        '';

        # --- Class 2: omarchy-nvim starter (seeded once) ---
        # Upstream ships a LazyVim starter + omarchy overlay as the
        # omarchy-nvim Arch package; the vendored config/ tree has no nvim
        # dir, so the starter comes from pkgs/omarchy-nvim.nix. Its
        # omarchy-nvim-setup script seeds ~/.config/nvim (writable copies,
        # plus the theme.lua symlink into ~/.local/state/omarchy/current/
        # theme). Seed-if-absent like the other stubs: user edits survive.
        home.activation.omarchyNvimSeed = lib.hm.dag.entryAfter [ "omarchySeedUserConfig" ] (
          lib.optionalString (effNvimPkg != null) ''
            if [ ! -e "$HOME/.config/nvim" ]; then
              "${effNvimPkg}/bin/omarchy-nvim-setup" >/dev/null 2>&1 || true
            fi
          ''
        );

        # --- Class 3: render the default theme into the state dir ---
        # Upstream populates ~/.local/state/omarchy/current/theme as a REAL
        # directory: omarchy-theme-set copies the chosen theme's colors.toml
        # into a staging dir, runs omarchy-theme-set-templates (a bash+sed
        # engine over default/themed/*.tpl) to render 16 per-app configs
        # (foot.ini, shell.toml, hyprland.lua, alacritty.toml, ...), then
        # atomically swaps the staging dir into place. foot.ini (seeded above)
        # has `include=~/.local/state/omarchy/current/theme/foot.ini`, Hyprland
        # requires("omarchy.current.theme.hyprland"), quickshell reads
        # current/theme/shell.toml — all of them miss unless the theme is
        # actually rendered, not just symlinked at the source dir (which only
        # carries colors.toml + backgrounds).
        #
        # Run the upstream renderer headless (no Hyprland/D-Bus available
        # during home-manager activation). OMARCHY_THEME_HEADLESS=1 skips the
        # omarchy-shell IPC call and all post-theme hooks
        # (omarchy-restart-*, omarchy-theme-set-*) that need a live session —
        # exactly the same path upstream takes during ISO chroot finalization.
        # PATH must include $OMARCHY_PATH/bin because the renderer calls its
        # sibling helpers (omarchy-theme-color, omarchy-theme-set-templates)
        # bare via PATH.
        #
        # Guard on current/theme.name: render only on the first activation.
        # `omarchy theme set <name>` (and this activation) write that file, so
        # a user who switches themes at runtime keeps their choice across
        # switches instead of being reset to omarchy.theme.
        home.activation.omarchyThemeRender =
          lib.hm.dag.entryAfter
            [
              "omarchySeedUserConfig"
              "linkGeneration"
            ]
            ''
              omarchy_state="$HOME/.local/state/omarchy"
              if [ ! -e "$omarchy_state/current/theme.name" ]; then
                omarchy_pkg="${omarchyPathOf effPkg}"
                PATH="$omarchy_pkg/bin:$PATH" \
                OMARCHY_PATH="$omarchy_pkg" \
                OMARCHY_THEME_HEADLESS=1 \
                  "$omarchy_pkg/bin/omarchy-theme-set" "${effTheme}" >/dev/null
              fi
            '';

        # --- Class 4: first-run skip markers (invitation-only) ---

        # default/hypr/autostart.lua runs omarchy-first-run on every login.
        # install/ is vendored (see pkgs/omarchy.nix), so first-run and
        # finalize-user run for real. Do NOT pre-create first-run-user /
        # finalize-user — those are the top-level completion markers
        # upstream writes only after a successful run.
        #
        # omarchy-done markers are flat files under
        # ~/.local/state/omarchy/done/<name> (no path components; see
        # bin/omarchy-done). Per-step markers exist ONLY for the two
        # invitation hooks (omarchy-done ensure inside the hook bodies):
        #   - voxtype-install-invitation  (Arch tarball / omarchy-voxtype-install)
        #   - fingerprint-setup-invitation (PAM/fprintd — out of scope)
        # Pre-create those so install/user/first-run/*.hook still get
        # installed by first-run, but never fire their invitation toasts.
        # Arch mise steps have no markers — they are no-op'd in the package.
        home.activation.omarchyFirstRunSkipMarkers = lib.hm.dag.entryAfter [ "omarchyThemeRender" ] ''
          omarchy_done="$HOME/.local/state/omarchy/done"
          mkdir -p "$omarchy_done"
          for marker in voxtype-install-invitation fingerprint-setup-invitation; do
            if [ ! -e "$omarchy_done/$marker" ]; then
              touch "$omarchy_done/$marker"
            fi
          done
        '';

        # --- Class 5: default browser (upstream finalize-user parity) ---

        # bin/omarchy-finalize-user:105 runs
        #   env -u BROWSER xdg-settings set default-web-browser chromium.desktop
        # env -u BROWSER is required: xdg-settings refuses to write the
        # association when BROWSER is set (treats it as a higher-priority
        # override). Idempotent — re-running just rewrites the same default.
        # Fail soft: activation has no graphical session, and some xdg-utils
        # backends need a DE; the || true keeps switch non-fatal. A later
        # session-side oneshot (first-run) can reassert if needed.
        home.activation.omarchyDefaultBrowser = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if command -v xdg-settings >/dev/null 2>&1; then
            env -u BROWSER xdg-settings set default-web-browser chromium.desktop >/dev/null 2>&1 || true
          fi
        '';
      }
    );
}
