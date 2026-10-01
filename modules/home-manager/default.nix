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
#      omarchy-symlink guard (pattern from HM programs/t3code.nix + gpg.nix)
#   2. Vendored defaults -> NOT copied; bootstrap.lua loads them from
#      $OMARCHY_PATH via package.path
# Paths Home Manager itself manages (home.file, xdg.configFile, ... -- e.g.
# programs.git owns ~/.config/git/config) are never seeded: they belong to
# the user's HM configuration.
#
# Where the omarchy.* values come from: under NixOS (osConfig.omarchy
# exists) the system configuration is the single source -- package,
# nvimPackage, theme, scale and monitors are read from osConfig.omarchy, and
# a differing value set here in Home Manager is ignored with an evaluation
# warning. Standalone Home Manager reads this module's own omarchy.*; the
# flake's homeModules.default injects package/nvimPackage there. Options
# this module never reads (everything else but enable) warn when set here.
# The values are read directly rather than mirrored (`omarchy =
# osConfig.omarchy` inside `mkIf cfg.enable` would form an evaluation
# cycle: cfg.enable <- mirror <- config.omarchy <- cfg.enable);
# omarchy.enable stays an HM-local switch.
{
  config,
  lib,
  pkgs,
  options,
  osConfig ? { },
  ...
}:

let
  # The vendored upstream config/ tree lives in the (read-only) store and is
  # the source of truth for the user-editable stubs. Reading from it (rather
  # than copying files into this repo) honors "vendor, don't rewrite".
  upstreamConfig = pkg: "${pkg}/share/omarchy/config";
  omarchyPathOf = pkg: "${pkg}/share/omarchy";

  # Targets Home Manager links itself, relative to $HOME: home.file, which
  # also carries xdg.configFile/dataFile/stateFile.
  hmTargets = map (file: file.target) (
    lib.filter (file: file.enable) (lib.attrValues config.home.file)
  );
  # Whether Home Manager manages the path or one of its parent directories.
  # Seeding there would replace HM's link with a copy (or write into a
  # read-only store directory), and HM's next activation aborts on the file
  # it no longer recognizes ("would be clobbered").
  hmManages = target: lib.any (t: t == target || lib.hasPrefix "${t}/" target) hmTargets;

  # Seed a user-editable file only if it does not already exist (or is a
  # legacy symlink into an omarchy tree, from older module versions that
  # used xdg.configFile). Any other symlink -- HM's own, another dotfile
  # manager's -- belongs to someone else and is left alone.
  # The first home-manager switch copies the upstream template; later switches
  # never touch a real file, so user edits survive. `cp -a` (not `ln -s`)
  # produces a regular file the user can edit. chmod u+w makes it actually
  # writable — cp -a preserves the store's read-only mode, but upstream
  # runtime tooling (omarchy-hyprland-monitor-scaling) writes to monitors.lua
  # via sed -i, and users need to edit all stubs. `run` keeps dry runs
  # (home-manager switch -n) read-only.
  # seedFileFrom takes a path relative to $HOME (for seeds that live outside
  # ~/.config, e.g. the skel parity files under ~/.local/share and
  # ~/.local/state); seedStubFrom is the ~/.config convenience wrapper.
  seedFileFrom =
    source: target:
    lib.optionalString (!hmManages target) ''
      omarchy_seed_target="$HOME/${target}"
      if { [ ! -e "$omarchy_seed_target" ] && [ ! -L "$omarchy_seed_target" ]; } \
        || { [ -L "$omarchy_seed_target" ] && [[ "$(readlink -m "$omarchy_seed_target")" == ${builtins.storeDir}/*/share/omarchy/* ]]; }; then
        run mkdir -p "$(dirname "$omarchy_seed_target")"
        run rm -f "$omarchy_seed_target"
        run cp -a "${source}" "$omarchy_seed_target"
        run chmod u+w "$omarchy_seed_target"
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
      effSkill = "${omarchyPathOf effPkg}/default/agents/skills/omarchy";

      # The omarchy.* values this module reads (the eff* above); every other
      # option except enable configures the NixOS module only.
      readHere = [
        "package"
        "nvimPackage"
        "theme"
        "scale"
        "monitors"
      ];
      # Options given a value in this Home Manager configuration (anything
      # above the option default's priority), omarchy.enable excepted, with
      # their path below omarchy (opt.loc also carries the
      # home-manager.users.<name> prefix under NixOS).
      setHere = lib.filter ({ opt, ... }: opt.highestPrio < (lib.mkOptionDefault null).priority) (
        lib.collect (leaf: leaf ? opt) (
          lib.mapAttrsRecursiveCond (attrs: !lib.isOption attrs) (path: opt: { inherit path opt; }) (
            removeAttrs options.omarchy [ "enable" ]
          )
        )
      );
      ignoredWarning =
        { path, opt }:
        let
          name = lib.showOption ([ "omarchy" ] ++ path);
        in
        if !lib.elem (lib.head path) readHere then
          "${name} is set in Home Manager, where it has no effect: only the omarchy NixOS module reads it. Set it in the NixOS configuration."
        else if osConfig ? omarchy && opt.value != lib.getAttrFromPath path osConfig.omarchy then
          "${name} is set in Home Manager, but under NixOS the omarchy Home Manager module uses the NixOS configuration's value (osConfig.${name}) instead. Set it in the NixOS configuration."
        else
          null;
    in
    lib.mkMerge [
      {
        warnings = lib.filter (warning: warning != null) (map ignoredWarning setHere);
        assertions = [
          {
            assertion = !cfg.enable || effPkg != null;
            message = "omarchy.enable is set in Home Manager, but no omarchy package is available, so nothing would be seeded. Import omarchy-nix's homeModules.default (it provides the package), or set omarchy.package -- in the NixOS configuration when Home Manager runs as a NixOS module.";
          }
        ];
      }

      (lib.mkIf (cfg.enable && effPkg != null) {
        # --- Class 0: agent skill links + default shell plugin (managed on
        # every activation) ---
        # Upstream finalize-user creates these six links once (v4.0.1 added
        # .gemini/config/skills and .hermes/skills; hermes per-profile skill
        # dirs are covered by migration 1787843905, which runs as user-safe).
        # On Arch their target is the stable /usr/share path, but on NixOS
        # OMARCHY_PATH is a generation-specific store path. A one-shot link
        # therefore keeps the old package after an update and eventually
        # becomes dangling after garbage collection. Home Manager owns the
        # same upstream paths and refreshes them to the active package at
        # every switch.
        #
        # Create all six agent skill dirs unconditionally (not gated on which
        # agents the user has installed) so the links match upstream finalize-user.
        #
        # The Elsewhen plugin link this module managed after the 2026-09-19
        # bump is gone: upstream folded Elsewhen into the shell as the
        # first-party omarchy.elsewhen (349ecc0), so dropping the entry lets
        # Home Manager remove the old link and migration 1790528634 renames
        # the bar entry.
        #
        # Real files/dirs at these paths are relocated before linkGeneration
        # (omarchySkillLinkSafety) so a user-owned skill clone is never deleted.
        # The move is a write, so it runs after writeBoundary (nothing may be
        # written before HM's checks have passed) and through `run` (a dry
        # run only prints it).
        # Existing symlinks are left for HM to replace; force is still required
        # because linkGeneration cannot adopt unmanaged symlinks without it.
        home.activation.omarchySkillLinkSafety =
          lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
            ''
              # Relocate real skill targets so home.file cannot delete user data.
              # Symlinks are left alone — force = true adopts/replaces them.
              omarchy_skill_ts="$(date -u +%Y%m%dT%H%M%SZ)"
              for omarchy_skill_rel in \
                .agents/skills/omarchy \
                .claude/skills/omarchy \
                .codex/skills/omarchy \
                .pi/agent/skills/omarchy \
                .gemini/config/skills/omarchy \
                .hermes/skills/omarchy
              do
                omarchy_skill_target="$HOME/$omarchy_skill_rel"
                # -e is false for a dangling symlink; -L catches those too, but
                # we only relocate real files/dirs — leave every symlink for force.
                if [ -e "$omarchy_skill_target" ] && [ ! -L "$omarchy_skill_target" ]; then
                  omarchy_skill_backup="''${omarchy_skill_target}.hm-backup-''${omarchy_skill_ts}"
                  echo "warning: omarchy managed link target $omarchy_skill_target is a real file/directory; moving aside to $omarchy_skill_backup before linking" >&2
                  run mv "$omarchy_skill_target" "$omarchy_skill_backup"
                fi
              done
            '';

        home.file =
          lib.genAttrs
            [
              ".agents/skills/omarchy"
              ".claude/skills/omarchy"
              ".codex/skills/omarchy"
              ".pi/agent/skills/omarchy"
              ".gemini/config/skills/omarchy"
              ".hermes/skills/omarchy"
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
        # Legacy symlinks into an omarchy tree (from older module versions
        # that used xdg.configFile) are replaced on the next switch. Files
        # the user's Home Manager configuration manages itself (e.g.
        # git/config under programs.git, starship.toml under
        # programs.starship) are skipped at evaluation time; see hmManages.
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
          ${seedStub effPkg "wireplumber/wireplumber.conf.d/kef-lsx-no-suspend.conf"}

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

          # --- ~/.bashrc (/etc/skel parity): upstream's default/bashrc
          # sources $OMARCHY_PATH/default/bash/rc (aliases, functions,
          # starship, zoxide, fzf key bindings). Seeded only when absent.
          # Unlike seedFileFrom, an existing ~/.bashrc is never replaced,
          # not even a store symlink: that is HM's programs.bash or another
          # dotfile manager owning the file. Kept verbatim (its guarded
          # /usr/share env-bootstrap line is inert here) so upstream
          # migrations still recognize the default file.
          if [ ! -e "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
            run cp -a "${omarchyPathOf effPkg}/default/bashrc" "$HOME/.bashrc"
            run chmod u+w "$HOME/.bashrc"
          fi

          # --- voxtype dictation config. Upstream copies this in
          # omarchy-voxtype-install; the package is shipped declaratively
          # (runtimeDeps), so seed the default config up front — the install
          # script's later cp is then a no-op over identical content.
          ${seedStubFrom "${omarchyPathOf effPkg}/default/voxtype/config.toml" "voxtype/config.toml"}

          # --- fastfetch config (upstream etc/fastfetch/config.jsonc; on Arch
          # the ISO copies it to /etc/fastfetch). Gives omarchy-launch-about
          # the branded layout (logo from ~/.config/omarchy/branding/about.txt
          # seeded above, omarchy-version* command modules). Mutable seed —
          # users can restyle fastfetch without a rebuild.
          ${seedStubFrom "${omarchyPathOf effPkg}/etc/fastfetch/config.jsonc" "fastfetch/config.jsonc"}
        '';

        # --- Class 2: omarchy-nvim starter (seeded once) ---
        # Upstream ships a LazyVim starter + omarchy overlay as the
        # omarchy-nvim Arch package; the vendored config/ tree has no nvim
        # dir, so the starter comes from pkgs/omarchy-nvim.nix. Its
        # omarchy-nvim-setup script seeds ~/.config/nvim (writable copies,
        # plus the theme.lua symlink into ~/.local/state/omarchy/current/
        # theme). Seed-if-absent like the other stubs: user edits survive.
        #
        # The script runs against a staging $HOME, and its config (and data)
        # dir is renamed into place only after it succeeded: a failed or
        # interrupted seed leaves no half-written ~/.config/nvim behind, so
        # the next activation retries it, and the failure is reported on
        # stderr instead of swallowed. xdg-utils is on its PATH for the
        # script's trailing `xdg-mime default` calls (absent from the
        # activation PATH, they used to abort it). With XDG_CONFIG_HOME
        # staged those write a mimeapps.list that is discarded, so the
        # user's ~/.config/mimeapps.list (possibly HM's xdg.mimeApps link)
        # is never touched; the nvim associations never reached it before
        # either.
        home.activation.omarchyNvimSeed = lib.hm.dag.entryAfter [ "omarchySeedUserConfig" ] (
          lib.optionalString (effNvimPkg != null) ''
            if [ ! -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
              if [[ -v DRY_RUN ]]; then
                echo "${effNvimPkg}/bin/omarchy-nvim-setup (staged, then moved to $HOME/.config/nvim)"
              else
                omarchy_nvim_stage="$HOME/.local/state/omarchy/nvim-seed"
                rm -rf "$omarchy_nvim_stage"
                mkdir -p "$omarchy_nvim_stage"
                if omarchy_nvim_log="$(
                  HOME="$omarchy_nvim_stage" \
                  XDG_CONFIG_HOME="$omarchy_nvim_stage/.config" \
                  XDG_DATA_HOME="$omarchy_nvim_stage/.local/share" \
                  PATH="${lib.makeBinPath [ pkgs.xdg-utils ]}:$PATH" \
                    "${effNvimPkg}/bin/omarchy-nvim-setup" 2>&1
                )" && [ -d "$omarchy_nvim_stage/.config/nvim" ] \
                  && mkdir -p "$HOME/.config" \
                  && mv -T "$omarchy_nvim_stage/.config/nvim" "$HOME/.config/nvim"; then
                  if [ ! -e "$HOME/.local/share/nvim" ] && [ -d "$omarchy_nvim_stage/.local/share/nvim" ]; then
                    mkdir -p "$HOME/.local/share"
                    mv -T "$omarchy_nvim_stage/.local/share/nvim" "$HOME/.local/share/nvim" || true
                  fi
                else
                  echo "warning: seeding ~/.config/nvim with omarchy-nvim-setup failed; retrying on the next activation. Output:" >&2
                  printf '%s\n' "''${omarchy_nvim_log:-}" >&2
                fi
                rm -rf "$omarchy_nvim_stage"
              fi
            fi
          ''
        );

        # --- Class 3: render the default theme into the state dir ---
        # Upstream populates ~/.local/state/omarchy/current/theme as a REAL
        # directory: omarchy-theme-set copies the chosen theme's colors.toml
        # into a staging dir, runs omarchy-theme-set-templates (a bash+sed
        # engine over default/themed/*.tpl) to render 19 per-app configs
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
                # The activation PATH lacks awk and flock, which the
                # template renderer (one awk pass) and theme-set's lock
                # need since 349ecc0; without them the render half-fails
                # silently and first-run's theme.sh aborts provision-user.
                PATH="$omarchy_pkg/bin:${
                  lib.makeBinPath [
                    pkgs.gawk
                    pkgs.util-linux
                  ]
                }:$PATH" \
                OMARCHY_PATH="$omarchy_pkg" \
                OMARCHY_THEME_HEADLESS=1 \
                  run --silence "$omarchy_pkg/bin/omarchy-theme-set" "${effTheme}" \
                  || echo "warning: failed to render omarchy theme '${effTheme}'; apply later with: omarchy-theme-set ${effTheme}" >&2 || true
              fi
            '';

        # --- Class 4: first-run skip markers (invitation-only) ---

        # default/hypr/autostart.lua runs omarchy-provision-first-run on every
        # login. install/ is vendored (see pkgs/omarchy.nix), so first-run and
        # provision-user run for real. Do NOT pre-create first-run-user /
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
          run mkdir -p "$omarchy_done"
          for marker in voxtype-install-invitation fingerprint-setup-invitation; do
            if [ ! -e "$omarchy_done/$marker" ]; then
              run touch "$omarchy_done/$marker"
            fi
          done
        '';

        # --- Class 5: default browser (upstream provision-user parity) ---

        # bin/omarchy-provision-user runs
        #   env -u BROWSER xdg-settings set default-web-browser chromium.desktop
        # env -u BROWSER is required: xdg-settings refuses to write the
        # association when BROWSER is set (treats it as a higher-priority
        # override). Initialize the association only when it is absent; a
        # user's later browser choice must survive a home-manager switch. The
        # first-run session path still runs the upstream command once behind
        # its finalize-user marker.
        #
        # The activation PATH is Home Manager's own tool set
        # (emptyActivationPath), without xdg-utils: the tools are called by
        # store path. Skipped when Home Manager manages mimeapps.list
        # (xdg.mimeApps): xdg-settings would replace HM's link with a file
        # and the next switch would abort on it.
        home.activation.omarchyDefaultBrowser = lib.hm.dag.entryAfter [ "linkGeneration" ] (
          lib.optionalString (!hmManages ".config/mimeapps.list") (
            let
              xdgSettings = "${pkgs.coreutils}/bin/env -u BROWSER ${pkgs.xdg-utils}/bin/xdg-settings";
            in
            ''
              if omarchy_default_browser="$(${xdgSettings} get default-web-browser 2>/dev/null)"; then
                if [ -z "$omarchy_default_browser" ]; then
                  run --silence ${xdgSettings} set default-web-browser chromium.desktop || true
                fi
              fi
            ''
          )
        );
      })
    ];
}
