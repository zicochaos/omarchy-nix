# omarchy vendoring derivation.
#
# Packages the upstream basecamp/omarchy (quattro) tree at
# $out/share/omarchy — the NixOS analogue of pacman's /usr/share/omarchy.
#
# Design (Stage 2): this is a *vendoring* derivation, not a rewrite. We copy
# the upstream tree verbatim and make exactly one adjustment: the
# single-source-of-truth file `default/bash/env-bootstrap` is patched so its
# default OMARCHY_PATH points at $out/share/omarchy instead of the Arch
# /usr/share/omarchy. Every other consumer (62 bin scripts, the Lua Hyprland
# bootstrap, etc.) reads OMARCHY_PATH from the environment, which the NixOS
# module (Stage 3) sets as a session variable. Hardcoded /usr/share/omarchy
# references in operational scripts (omarchy-finalize-user, omarchy-upgrade-*,
# omarchy-dev-link) are intentionally NOT patched: those are Arch/pacman
# lifecycle scripts that have no NixOS analogue and would require translation,
# which is explicitly out of scope (AGENTS.md: "vendor, don't rewrite").
#
# Path adaptation also covers:
#   - the 7 systemd user units under default/systemd/user/ (/usr/bin/* and
#     /usr/share/omarchy → store paths). Unit semantics, [Install] targets,
#     and ordering are left untouched.
#   - install/user/xcompose.sh (hardcoded include path for default/xcompose).
#   - install/user/mise{,-work}.sh: no-op stubs. Upstream has no per-step
#     omarchy-done markers for these (only top-level finalize-user /
#     first-run-user + invitation markers); without a no-op they abort
#     finalize-user under set -e before keyring/xdg steps. mise is Arch
#     packaging (/opt/packages tarballs) and out of scope for this port.
#   - install/ + applications/ are vendored so omarchy-first-run /
#     omarchy-finalize-user / omarchy-refresh-applications resolve
#     $OMARCHY_PATH/install and $OMARCHY_PATH/applications (OMARCHY_INSTALL
#     defaults to $OMARCHY_PATH/install).
#   - store→$HOME copies in bin/ and install/user/hardware/asus/: add
#     --no-preserve=mode so cp does not inherit the store's 444/555 modes
#     (which break theme swaps, config refresh, and branding edits).
#   - Update/Install/Remove (P4): pacman-coupled bin scripts become NixOS-
#     native or no-op stubs; omarchy-update-system-pkgs runs
#     `nix flake update` + `nixos-rebuild switch` against the consumer
#     flake; menu install.package/remove.package call the nix-native
#     pickers (omarchy-nix-search / omarchy-nix-remove), the AUR entry is
#     deleted outright.
{
  omarchy-src,
  version,
  stdenv,
  lib,
  fcitx5,
  bluez-tools,
  pipewire,
  systemd,
  tailscale,
  writeText,
  glib,
  makeWrapper,
  python3,
}:

let
  # omarchy-file-select is the tree's only Python script: it needs
  # pygobject3 (gi.repository.Gio/GLib) at runtime. The withPackages
  # interpreter is substituted into its /usr/bin/python3 shebang in postPatch
  # (the automatic patchShebangs cannot resolve /usr/bin/python3 without
  # python on the fixup PATH, so we substitute explicitly).
  pythonWithGi = python3.withPackages (ps: [ ps.pygobject3 ]);

  # Classification of Arch system mutators: declarative-note
  # scripts become generated stubs below; checks.omarchy-runtime enforces
  # the manifest against the packaged tree (fail-closed on new upstream
  # mutators at bump time).
  runtimeManifest = import ./omarchy-runtime-manifest.nix;

  # Menu lines for the cataloged coding agents, inserted into
  # default/omarchy/omarchy-menu.jsonc after the install.ai.ollama entry in
  # postPatch. One entry per install.ai.* catalog id (the catalog-consistency
  # check requires every catalog id to appear in the menu).
  agentMenuEntries = writeText "agent-menu-entries.jsonc" ''
    "install.ai.claude": {"icon":"󱚤","label":"Claude Code","when":"! omarchy-pkg-present claude-code","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.claude'"},
    "install.ai.codex": {"icon":"󱚤","label":"Codex","when":"! omarchy-pkg-present codex-cli","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.codex'"},
    "install.ai.copilot": {"icon":"󱚤","label":"GitHub Copilot","when":"! omarchy-pkg-present github-copilot-cli","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.copilot'"},
    "install.ai.crush": {"icon":"󱚤","label":"Crush","when":"! omarchy-pkg-present crush-bin","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.crush'"},
    "install.ai.gemini": {"icon":"󱚤","label":"Gemini","when":"! omarchy-pkg-present gemini-cli","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.gemini'"},
    "install.ai.grok": {"icon":"󱚤","label":"Grok","when":"! omarchy-pkg-present grok-cli","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.grok'"},
    "install.ai.opencode": {"icon":"󱚤","label":"OpenCode","when":"! omarchy-pkg-present opencode","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.opencode'"},
    "install.ai.pi": {"icon":"󱚤","label":"Pi","when":"! omarchy-pkg-present pi-coding-agent","action":"omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.pi'"},
  '';
in

stdenv.mkDerivation (finalAttrs: {
  pname = "omarchy";
  # The upstream `version` file (e.g. "4.0.0.alpha") carries a trailing
  # newline; trim it so `nix derivation show` and meta.position stay clean.
  version = lib.trim version;

  src = omarchy-src;

  # Patch the single source of truth for OMARCHY_PATH so the packaged default
  # resolves to this derivation's output. Other files (default/hypr/paths.lua,
  # default/hypr/bootstrap.lua) already read OMARCHY_PATH from the environment
  # and only fall back to /usr/share/omarchy — that fallback is left intact
  # because the NixOS module always sets the var.
  #
  # Also path-adapt the systemd user units: /usr/bin/* is dead on NixOS.
  # Units are later installed to $out/lib/systemd/user/ for systemd.packages.
  postPatch = ''
        substituteInPlace default/bash/env-bootstrap \
          --replace-fail "/usr/share/omarchy" "$out/share/omarchy"

        # The tree's only Python script: /usr/bin/python3 is dead
        # on NixOS. Point it at the pygobject3-enabled store interpreter; the
        # GI_TYPELIB_PATH wrap happens in postFixup.
        substituteInPlace bin/omarchy-file-select \
          --replace-fail '#!/usr/bin/python3' '#!${pythonWithGi}/bin/python3'

        # model-usage plugin: the QML providers exec a bare `python3` (dead
        # on a minimal session PATH) and the scanner scripts carry an
        # env-python shebang. Point both at the store interpreter (the
        # scanners are stdlib-only, no pygobject needed).
        substituteInPlace shell/plugins/model-usage/providers/Claude.qml \
          --replace-fail '"python3", root.projectScannerScriptPath' '"${python3}/bin/python3", root.projectScannerScriptPath'
        substituteInPlace shell/plugins/model-usage/providers/Codex.qml \
          --replace-fail '"python3", root.scannerPath' '"${python3}/bin/python3", root.scannerPath'
        substituteInPlace shell/plugins/model-usage/scripts/claude_usage_scanner.py \
          --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python3'

        # --- systemd user units: binary + omarchy path adaptation only ---
        # bt-agent lives in bluez-tools on nixpkgs (not bluez).
        substituteInPlace default/systemd/user/bt-agent.service \
          --replace-fail "/usr/bin/systemctl" "${systemd}/bin/systemctl" \
          --replace-fail "/usr/bin/bt-agent" "${bluez-tools}/bin/bt-agent"

        substituteInPlace default/systemd/user/omarchy-fcitx5.service \
          --replace-fail "/usr/bin/fcitx5" "${fcitx5}/bin/fcitx5"

        substituteInPlace default/systemd/user/omarchy-migrate-notify.service \
          --replace-fail "ConditionPathIsDirectory=/usr/share/omarchy/migrations" \
            "ConditionPathIsDirectory=$out/share/omarchy/migrations" \
          --replace-fail "/usr/bin/omarchy-migrate-notify" \
            "$out/share/omarchy/bin/omarchy-migrate-notify"

        substituteInPlace default/systemd/user/omarchy-recover-internal-monitor.service \
          --replace-fail "/usr/bin/omarchy-hw-recover-internal-monitor" \
            "$out/share/omarchy/bin/omarchy-hw-recover-internal-monitor"

        substituteInPlace default/systemd/user/omarchy-sleep-lock.service \
          --replace-fail "/usr/bin/omarchy-system-sleep-monitor" \
            "$out/share/omarchy/bin/omarchy-system-sleep-monitor"

        # pipewire -c omarchy-speaker-tuning.conf keeps the relative conf name:
        # omarchy-audio-tuning installs the host conf + fragments under
        # ~/.config/pipewire/ at runtime. Only the binary path needs adapting.
        substituteInPlace default/systemd/user/omarchy-speaker-tuning.service \
          --replace-fail "/usr/bin/pipewire" "${pipewire}/bin/pipewire"

        substituteInPlace default/systemd/user/omarchy-tailscale-receive.service \
          --replace-fail "ConditionPathExists=/usr/bin/tailscale" \
            "ConditionPathExists=${tailscale}/bin/tailscale" \
          --replace-fail "/usr/bin/omarchy-tailscale-receive" \
            "$out/share/omarchy/bin/omarchy-tailscale-receive"

        # omarchy-launch-browser resolves the .desktop via a fixed brace list of
        # data dirs. Arch has /usr/share/applications; NixOS puts system apps in
        # /run/current-system/sw/share/applications. Add that path so chromium
        # (and any other default) resolves after xdg-settings.
        substituteInPlace bin/omarchy-launch-browser \
          --replace-fail \
            '{~/.local,~/.nix-profile,/usr}/share/applications' \
            '{~/.local,~/.nix-profile,/run/current-system/sw,/usr}/share/applications'

        # chromium-flags.conf seed: --load-extension points at the Arch
        # /usr/share/omarchy. Point it at the system-profile path instead —
        # stable across rebuilds (/share/omarchy is in environment.pathsToLink,
        # so /run/current-system/sw/share/omarchy always resolves to the active
        # omarchy package). HM seeds this file; existing user copies are fixed
        # by migration adapter 1780517689.sh.
        substituteInPlace config/chromium-flags.conf \
          --replace-fail "/usr/share/omarchy" "/run/current-system/sw/share/omarchy"

        # Same durability problem in the native-messaging-host installers:
        # they embed $OMARCHY_PATH (a store path) into
        # ~/.config/*/NativeMessagingHosts/*.json, so a rebuild + GC kills
        # Alt+Shift+D / copy-url silently, and the once-only migrations never
        # re-register. Point HOST_PATH at the stable system-profile path.
        substituteInPlace bin/omarchy-install-chromium-ytdlp bin/omarchy-install-chromium-copy-url \
          --replace-fail 'HOST_PATH="$OMARCHY_PATH/bin/' 'HOST_PATH="/run/current-system/sw/share/omarchy/bin/'

        # --- first-run / finalize-user path + platform adaptation ---
        # xcompose.sh tees ~/.XCompose with a hardcoded Arch include path.
        substituteInPlace install/user/xcompose.sh \
          --replace-fail 'include "/usr/share/omarchy/default/xcompose"' \
          "include \"$out/share/omarchy/default/xcompose\""

        # mise is Arch packaging (tarballs under /opt/packages, omarchy-mise-install
        # wrappers). Upstream runs these from install/user/all.sh and again from
        # omarchy-refresh-applications with no per-step skip marker; under
        # finalize-user's set -e a missing `mise` aborts before default-keyring.
        # Keep the files so orchestration paths stay intact; make the bodies no-ops.
        cat > install/user/mise.sh <<'EOF'
    # omarchy-nix: mise is Arch packaging; intentionally no-op on NixOS.
    exit 0
    EOF
        cat > install/user/mise-work.sh <<'EOF'
    # omarchy-nix: mise-work is Arch packaging; intentionally no-op on NixOS.
    exit 0
    EOF

        # --- L4 adaptation: read-only inheritance fix ---
        # cp/cp -r from the read-only store ($OMARCHY_PATH) into $HOME
        # preserves the store's 444/555 modes, leaving user configs, theme
        # state and .desktop files unwritable (and making rm -rf of a staged
        # theme dir fail, which breaks omarchy-theme-set's atomic swap).
        # Add --no-preserve=mode to every store->$HOME copy. sudo copies into
        # Arch system paths (/etc, /boot, /usr/lib) are intentionally untouched.
        # omarchy-theme-set additionally gets defensive chmod -R u+w before its
        # rm -rf calls so pre-fix installs with read-only 555/444 debris in
        # ~/.local/state/omarchy/current/ self-heal on the next theme switch.
        substituteInPlace bin/omarchy-theme-set \
          --replace-fail 'cp -r "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/" 2>/dev/null' \
                         'cp -r --no-preserve=mode "$OMARCHY_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/" 2>/dev/null' \
          --replace-fail 'cp -r "$USER_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/" 2>/dev/null' \
                         'cp -r --no-preserve=mode "$USER_THEMES_PATH/$THEME_NAME/"* "$NEXT_THEME_PATH/" 2>/dev/null' \
          --replace-fail 'rm -rf "$NEXT_THEME_PATH"' \
                         'chmod -R u+w "$NEXT_THEME_PATH" 2>/dev/null; rm -rf "$NEXT_THEME_PATH"' \
          --replace-fail 'rm -rf "$CURRENT_THEME_PATH"' \
                         'chmod -R u+w "$CURRENT_THEME_PATH" 2>/dev/null; rm -rf "$CURRENT_THEME_PATH"'

        substituteInPlace bin/omarchy-refresh-config \
          --replace-fail 'cp -f "$default_config_file" "$user_config_file"' \
                         'cp -f --no-preserve=mode "$default_config_file" "$user_config_file"'

        substituteInPlace bin/omarchy-refresh-hyprland \
          --replace-fail 'cp "$OMARCHY_PATH/default/hypr/toggles/flags.lua"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/default/hypr/toggles/flags.lua"'

        substituteInPlace bin/omarchy-branding-screensaver \
          --replace-fail 'cp "$OMARCHY_PATH/logo.txt"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/logo.txt"'
        substituteInPlace bin/omarchy-branding-about \
          --replace-fail 'cp "$OMARCHY_PATH/icon.txt"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/icon.txt"'

        # nixpkgs wraps tte with makeWrapper, so the process comm is
        # ".tte-wrapped" and `pgrep/pkill -x tte` never match. The
        # screensaver's inner wait loop then exits instantly and the outer
        # while-true respawns tte in a tight loop (~300MB RSS each) until
        # the kernel OOM-kills the whole session. Tolerate both the bare
        # and the wrapped comm name (ERE, anchored by -x). Keep the pattern
        # <=15 chars: without -f, pgrep/pkill warn "pattern ... longer than
        # 15 characters" on EVERY call — and this pgrep runs once per second
        # in the wait loop, so the warnings pile up in the terminal buffer
        # behind the tte canvas and flash at every effect change.
        substituteInPlace bin/omarchy-screensaver \
          --replace-fail 'pgrep -t "''${tty#/dev/}" -x tte' \
                         'pgrep -t "''${tty#/dev/}" -x "\.?tte.*"' \
          --replace-fail 'pkill -x tte' \
                         'pkill -x "\.?tte.*"'

        # Same wrapper class of bug as tte above: nixpkgs wraps
        # gpu-screen-recorder, so the recorded process cmdline is the full
        # store path (/nix/store/...gpu-screen-recorder-*/bin/.wrapped/
        # gpu-screen-recorder ...) and `pgrep/pkill -f "^gpu-screen-recorder"`
        # never matches — recording starts but the bar indicator stays dark
        # and --stop-recording silently does nothing (verified on real
        # hardware: recorder kept capturing after "stop"). Match the path
        # segment with
        # a trailing space instead: it hits the wrapped cmdline ("...
        # /gpu-screen-recorder -w ...") but NOT gsr-kms-server (whose path
        # continues "-5.x.y/bin/gsr-kms-server", no space after the name).
        #
        # The pattern is bracketed (`[/]`) for a second reason — indicator
        # self-latching (root-caused on real hardware via an instrumented
        # shell):
        # Indicators.qml always instantiates BOTH its horizontal and vertical
        # blocks (visibility-gated, not loader-gated), so every indicator
        # exists twice and each instance runs its own statusProc pgrep at
        # startup. pgrep excludes only its own PID, and each pgrep's cmdline
        # contains the pattern text — so with a plain pattern the two
        # concurrent pgreps match EACH OTHER and both exit 0. On a cold boot
        # pgrep takes ~130ms, so the event-loop-synchronized starts always
        # overlap and recording latches true at every login (the QML's
        # activeStateObserved guard then pins it forever). The bracket keeps
        # matching the real recorder while the pgreps' own cmdlines (literal
        # "[/]gpu…") no longer match. Same trick as the menu `when:` guard.
        substituteInPlace bin/omarchy-capture-screenrecording \
          --replace-fail '"^gpu-screen-recorder"' \
                         '"[/]gpu-screen-recorder "'
        substituteInPlace shell/plugins/bar/indicators/ScreenRecording.qml \
          --replace-fail '"^gpu-screen-recorder"' \
                         '"[/]gpu-screen-recorder "'

        # Same fix for the menu's `when:` guard, but with a self-match-safe
        # pattern: the menu batches all guards into ONE `bash -lc` process
        # whose cmdline contains the pattern text, so a plain substring
        # pattern would match the evaluator itself and "Stop Screenrecording"
        # would be visible ALWAYS. `[/]gpu-screen-recorder ` keeps matching
        # the wrapped recorder (/…/bin/.wrapped/gpu-screen-recorder -w …)
        # while matching neither the evaluator (literal "[/]gpu…" in its
        # cmdline) nor gsr-kms-server (path continues "-5.x.y/bin/…", no
        # space after the name).
        substituteInPlace default/omarchy/omarchy-menu.jsonc \
          --replace-fail "pgrep -f '^gpu-screen-recorder'" \
                         "pgrep -f '[/]gpu-screen-recorder '"

        substituteInPlace bin/omarchy-refresh-applications \
          --replace-fail 'cp "$OMARCHY_PATH"/applications/*.desktop' \
                         'cp --no-preserve=mode "$OMARCHY_PATH"/applications/*.desktop' \
          --replace-fail 'cp "$OMARCHY_PATH/default/alacritty/Alacritty.desktop"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/default/alacritty/Alacritty.desktop"'

        substituteInPlace bin/omarchy-install-terminal \
          --replace-fail 'cp "$OMARCHY_PATH/default/alacritty/$desktop_id"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/default/alacritty/$desktop_id"' \
          --replace-fail 'cp "$OMARCHY_PATH/applications/$desktop_id"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/applications/$desktop_id"' \
          --replace-fail 'cp -Rpf "$OMARCHY_PATH/config/$package"' \
                         'cp -Rpf --no-preserve=mode "$OMARCHY_PATH/config/$package"'

        substituteInPlace bin/omarchy-install-browser \
          --replace-fail 'cp -f "$OMARCHY_PATH/config/chromium-flags.conf" "$1"' \
                         'cp -f --no-preserve=mode "$OMARCHY_PATH/config/chromium-flags.conf" "$1"'

        substituteInPlace bin/omarchy-voxtype-install \
          --replace-fail 'cp "$OMARCHY_PATH/default/voxtype/config.toml"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/default/voxtype/config.toml"'

        substituteInPlace install/user/hardware/asus/fix-audio-mixer.sh \
          --replace-fail 'cp "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"' \
                         'cp --no-preserve=mode "$OMARCHY_PATH/default/wireplumber/wireplumber.conf.d/alsa-soft-mixer.conf"'

        # omarchy-plugin-clone copies plugin sources out of the store via the
        # catalog sourceDir with mode-preserving cp -aL: clones land in
        # ~/.config/omarchy/plugins as 444 files in 555 dirs — uneditable,
        # and the sed -i rename pass aborts on the read-only dirs. Menu-exposed
        # via Setup -> Plugin -> Clone since quattro f8835df6 (#6433). Same
        # L4 read-only-inheritance class as the copies above.
        substituteInPlace bin/omarchy-plugin-clone \
          --replace-fail 'cp -aL "$source_dir/." "$target_dir/"' \
                         'cp -aL --no-preserve=mode "$source_dir/." "$target_dir/"' \
          --replace-fail 'cp -aL "$manifest" "$target_dir/manifest.json"' \
                         'cp -aL --no-preserve=mode "$manifest" "$target_dir/manifest.json"' \
          --replace-fail 'cp -aL "$source_dir/$source/." "$target_dir/$target/"' \
                         'cp -aL --no-preserve=mode "$source_dir/$source/." "$target_dir/$target/"' \
          --replace-fail 'cp -aL "$source_dir/$source" "$target_dir/$target"' \
                         'cp -aL --no-preserve=mode "$source_dir/$source" "$target_dir/$target"'

        # --- L4 adaptation: Update / Install / Remove (P4) ---
        # Upstream's package lifecycle is pacman/yay/snapper. On NixOS the
        # system is declarative: keep the omarchy-update UX shell (logging,
        # lock, inhibitors, confirm, migrate, post-update hook, restart) but
        # replace the package-refresh core and stub every pacman helper so
        # direct invocation is safe and never mutates the system.

        # Helper writers (run during postPatch, not at package runtime).
        stub_declarative() {
          local path="$1"
          local name
          # Fail-closed: never create orphan stubs if upstream renamed/removed
          # the script — a missing target must surface at build time.
          if [[ ! -e "$path" ]]; then
            echo "omarchy-nix: stub_declarative target missing (upstream rename?): $path" >&2
            exit 1
          fi
          name=$(basename "$path")
          cat >"$path" <<EOF
    #!/bin/bash
    # omarchy-nix: $name is pacman/Arch packaging; packages are declarative on NixOS.
    echo "NixOS: packages are declarative — add packages to your flake config and nixos-rebuild switch (via $name)"
    exit 0
    EOF
          chmod +x "$path"
        }

        stub_handled() {
          local path="$1"
          local name
          # Fail-closed: never create orphan stubs if upstream renamed/removed
          # the script — a missing target must surface at build time.
          if [[ ! -e "$path" ]]; then
            echo "omarchy-nix: stub_handled target missing (upstream rename?): $path" >&2
            exit 1
          fi
          name=$(basename "$path")
          cat >"$path" <<EOF
    #!/bin/bash
    # omarchy-nix: $name has no NixOS analogue (pacman/AUR/mise/orphans).
    echo "NixOS: handled declaratively (via $name)"
    exit 0
    EOF
          chmod +x "$path"
        }

        # Package install/remove/channel/version helpers → declarative note.
        for s in \
          bin/omarchy-pkg-install \
          bin/omarchy-pkg-remove \
          bin/omarchy-pkg-add \
          bin/omarchy-pkg-drop \
          bin/omarchy-pkg-aur-add \
          bin/omarchy-pkg-aur-install \
          bin/omarchy-reinstall-pkgs \
          bin/omarchy-refresh-pacman \
          bin/omarchy-channel-set \
          bin/omarchy-version-channel \
          bin/omarchy-version-pkgs \
          bin/omarchy-upgrade-to-quattro \
          bin/omarchy-install-service-1password \
          bin/omarchy-install-service-dropbox \
          bin/omarchy-install-service-spotify \
          bin/omarchy-install-service-signal \
          bin/omarchy-install-service-tailscale \
          bin/omarchy-install-service-nordvpn \
          bin/omarchy-install-service-once
        do
          stub_declarative "$s"
        done

        # Update pipeline sub-steps that only make sense on Arch → no-op note.
        # when-conflicted recovers pacman file conflicts by moving unowned
        # files aside; its only caller is the B4-replaced update-system-pkgs.
        for s in \
          bin/omarchy-update-dev \
          bin/omarchy-update-keyring \
          bin/omarchy-update-aur-pkgs \
          bin/omarchy-update-mise \
          bin/omarchy-update-orphan-pkgs \
          bin/omarchy-update-pacman-guard \
          bin/omarchy-update-system-pkgs-when-conflicted
        do
          stub_handled "$s"
        done

        # AUR reachability check: report unavailable so any remaining caller
        # that gates on it skips AUR work cleanly.
        cat > bin/omarchy-pkg-aur-accessible <<'EOF'
    #!/bin/bash
    # omarchy-nix: no AUR on NixOS.
    exit 1
    EOF
        chmod +x bin/omarchy-pkg-aur-accessible

        # Lock/fingerprint PAM writers: upstream writes /etc/pam.d/*
        # imperatively; on NixOS those services are declared in the module
        # (blocks K/L), so runtime writes are both wrong and impossible.
        for s in \
          bin/omarchy-setup-lock \
          bin/omarchy-setup-security-fingerprint \
          bin/omarchy-remove-security-fingerprint
        do
          name=$(basename "$s")
          cat >"$s" <<EOF
    #!/bin/bash
    # omarchy-nix: $name writes /etc/pam.d/* on Arch; PAM services are
    # declarative on NixOS (security.pam.services, omarchy module blocks K/L).
    echo "NixOS: lock-screen PAM is declarative."
    echo "  omarchy-lock-password    — always present when omarchy.enable = true"
    echo "  omarchy-lock-fingerprint — set omarchy.fingerprint.enable = true in your flake, rebuild, then enroll with fprintd-enroll"
    echo "Overrides: security.pam.services.\"omarchy-lock-*\" (mkForce)."
    exit 0
    EOF
          chmod +x "$s"
        done

        # --- Arch system mutators -------------------------------------------
        # Upstream ships runtime commands that imperatively mutate NixOS-owned
        # system state (/etc/pam.d, sudoers, resolved.conf, fstab, systemctl
        # enable, ufw, mkinitcpio, modprobe, efibootmgr ...). Treatment per
        # pkgs/omarchy-runtime-manifest.nix: generated declarative-note stubs,
        # hand adaptations that keep the user-state flows, and menu entries
        # hidden where no NixOS runtime implementation exists.
        # checks.omarchy-runtime fails the build if a future upstream bump
        # adds a new unclassified mutator.

        # declarative-note stubs — generated from the manifest (single source
        # of truth; the runtime check re-verifies the result).
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: m: ''
                        cat >bin/${name} <<'OMARCHY_NIX_STUB'
            #!/bin/bash
            # omarchy-nix: upstream ${name} mutates Arch system state; on NixOS that
            # state is owned declaratively.
            echo "NixOS: ${m.note}"
            echo "(via ${name} — neutralized; nothing was changed)"
            exit 0
            OMARCHY_NIX_STUB
                        chmod +x bin/${name}
          '') (lib.filterAttrs (n: m: m.class == "declarative-note") runtimeManifest.scripts)
        )}

        # nixos-adapted (hand rewrites — user-state flows kept, system
        # mutations removed):

        # omarchy-setup-security-sshd: the daemon + firewall are declarative
        # (services.openssh.enable opens port 22 on NixOS); the useful
        # user-state subset — authorizing SSH keys — is kept.
        cat >bin/omarchy-setup-security-sshd <<'EOF'
    #!/bin/bash
    # omarchy:summary=Authorize an SSH public key (the sshd daemon is declarative on NixOS)
    # omarchy:args=[--key=<public-key>]
    # omarchy:examples=omarchy-setup-security-sshd | omarchy-setup-security-sshd --key="ssh-ed25519 AAAA... user@host"

    set -e

    AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"
    KEY=""

    for arg in "$@"; do
      case "$arg" in
      --key=*) KEY="''${arg#--key=}" ;;
      -h | --help)
        echo "Usage: omarchy-setup-security-sshd [--key=<public-key>]"
        echo
        echo "Authorizes an SSH key (from GitHub, pasted, or passed via --key)."
        echo "On NixOS the OpenSSH daemon itself is declarative:"
        echo "  services.openssh.enable = true  (opens the firewall port automatically)"
        exit 0
        ;;
      *)
        echo "omarchy-setup-security-sshd: unknown option '$arg'. Try --help." >&2
        exit 2
        ;;
      esac
    done

    valid_key() {
      ssh-keygen -lf /dev/stdin <<<"$1" >/dev/null 2>&1
    }

    authorize_key() {
      local key="$1"

      if ! valid_key "$key"; then
        echo -e "\e[31mNot a valid SSH public key: $key\e[0m" >&2
        return 1
      fi

      mkdir -p "$HOME/.ssh"
      chmod 700 "$HOME/.ssh"
      touch "$AUTHORIZED_KEYS"
      chmod 600 "$AUTHORIZED_KEYS"

      if grep -qxF "$key" "$AUTHORIZED_KEYS"; then
        echo "Key already authorized: $(ssh-keygen -lf /dev/stdin <<<"$key")"
      else
        echo "$key" >>"$AUTHORIZED_KEYS"
        echo "Authorized key: $(ssh-keygen -lf /dev/stdin <<<"$key")"
      fi
    }

    authorize_keys_from_github() {
      local username keys added=0

      username=$(gum input --prompt "GitHub username> " --placeholder "dhh") || exit 1
      if [[ -z $username ]]; then
        echo -e "\e[31mNo GitHub username given.\e[0m" >&2
        exit 1
      fi

      echo "Fetching keys from https://github.com/$username.keys..."
      if ! keys=$(curl -fsSL "https://github.com/$username.keys") || [[ -z $keys ]]; then
        echo -e "\e[31mCould not fetch any SSH keys for GitHub user '$username'.\e[0m" >&2
        exit 1
      fi

      while IFS= read -r key; do
        [[ -z $key ]] && continue
        authorize_key "$key" && added=$((added + 1))
      done <<<"$keys"

      if (( added == 0 )); then
        echo -e "\e[31mNo valid SSH keys found for GitHub user '$username'.\e[0m" >&2
        exit 1
      fi
    }

    authorize_pasted_key() {
      local key

      key=$(gum input --prompt "Public key> " --placeholder "ssh-ed25519 AAAA... user@host") || exit 1
      if [[ -z $key ]]; then
        echo -e "\e[31mNo SSH key given.\e[0m" >&2
        exit 1
      fi

      authorize_key "$key" || exit 1
    }

    echo -e "\e[32mSetting up SSH server access with key-based authentication.\n\e[0m"

    # omarchy-nix: the daemon + firewall are declarative on NixOS.
    if systemctl is-enabled --quiet sshd 2>/dev/null; then
      echo "OpenSSH daemon: enabled (managed declaratively — disable via services.openssh.enable = false)."
    else
      echo "OpenSSH daemon: NOT enabled."
      echo "  Enable it in your flake config: services.openssh.enable = true"
      echo "  (NixOS opens the firewall port automatically; no firewall rules needed.)"
    fi

    echo
    if [[ -n $KEY ]]; then
      authorize_key "$KEY" || exit 1
    else
      case $(gum choose "Grab key from GitHub" "Paste key manually" --header "How would you like to add your SSH key?") in
      "Grab key from GitHub") authorize_keys_from_github ;;
      "Paste key manually") authorize_pasted_key ;;
      *) exit 1 ;;
      esac
    fi

    echo -e "\e[32m\nDone — your key is authorized.\e[0m"
    echo "You can now connect with: ssh $USER@$(hostname)"
    EOF
        chmod +x bin/omarchy-setup-security-sshd

        # omarchy-remove-security-sshd: keep the authorized_keys cleanup
        # prompt; disabling the daemon is a flake edit + rebuild.
        cat >bin/omarchy-remove-security-sshd <<'EOF'
    #!/bin/bash
    # omarchy:summary=Remove authorized SSH keys (the sshd daemon is declarative on NixOS)
    # omarchy:requires-sudo=true

    set -e

    AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

    echo -e "\e[32mRemoving SSH server access.\n\e[0m"

    # omarchy-nix: the daemon + firewall are declarative on NixOS.
    if systemctl is-enabled --quiet sshd 2>/dev/null; then
      echo "OpenSSH daemon: currently enabled (managed declaratively)."
      echo "  To disable it: services.openssh.enable = false in your flake config, then rebuild."
    else
      echo "OpenSSH daemon: not enabled."
    fi

    if [[ -s $AUTHORIZED_KEYS ]]; then
      echo
      if gum confirm "Also remove all authorized SSH keys ($AUTHORIZED_KEYS)?"; then
        rm -f "$AUTHORIZED_KEYS"
        echo "Authorized keys removed."
      else
        echo "Keeping authorized keys."
      fi
    fi

    echo -e "\e[32m\nDone.\e[0m"
    EOF
        chmod +x bin/omarchy-remove-security-sshd

        # omarchy-remove-dev-env: mise/rustup/opam arms are user-level (kept);
        # the two pacman arms (php / symfony-cli) become a note.
        substituteInPlace bin/omarchy-remove-dev-env \
          --replace-fail 'sudo pacman -Rns --noconfirm php composer php-sqlite xdebug 2>/dev/null || true' \
                         'echo "NixOS: php/composer/xdebug system packages are declarative — remove them from your flake config (mise runtimes are removed below)."' \
          --replace-fail 'sudo pacman -Rns --noconfirm symfony-cli 2>/dev/null || true' \
                         'echo "NixOS: symfony-cli is declarative — remove it from your flake config and rebuild."'

        # omarchy-remove-launcher-entry: on NixOS a .desktop outside $HOME
        # belongs to a system package — point at omarchy-nix-remove instead of
        # the pacman owner probe + pacman -Rns branch.
        substituteInPlace bin/omarchy-remove-launcher-entry \
          --replace-fail 'if package_name="$(pacman -Qqo "$desktop_file" 2>/dev/null | head -1)" && [[ -n $package_name ]]; then' \
                         'if [[ $desktop_file == /nix/store/* || $desktop_file == /run/current-system/* ]]; then' \
          --replace-fail "  quoted_package=\"\$(printf '%q' \"\$package_name\")\"" \
                         "  # (pacman owner probe removed)" \
          --replace-fail "  quoted_display=\"\$(printf '%q' \"\$display_name\")\"" \
                         "  # (pacman uninstall branch removed)" \
          --replace-fail '  exec omarchy-launch-floating-terminal-with-presentation "echo Uninstalling $quoted_display...; sudo pacman -Rns $quoted_package"' \
                         '  echo "NixOS: $display_name is a system package — remove it with omarchy-nix-remove (Menu -> Remove) or from your flake config." >&2; exit 1'

        # omarchy-version: print the package version from the store path; the
        # pacman -Q fallback is gone (no Arch package database on NixOS).
        cat >bin/omarchy-version <<'EOF'
    #!/bin/bash
    # omarchy:summary=Print the installed Omarchy version

    omarchy_path=''${OMARCHY_PATH:-/usr/share/omarchy}
    omarchy_path=''${omarchy_path%/}

    # omarchy-nix: the package version lives in the store path
    # (/nix/store/<hash>-omarchy-<version>/share/omarchy).
    if [[ $omarchy_path == /nix/store/* ]]; then
      pkg_dir=''${omarchy_path%/share/omarchy}
      pkg_name=''${pkg_dir##*/}
      echo "''${pkg_name#*-omarchy-}"
      exit 0
    fi

    if [[ $omarchy_path != "/usr/share/omarchy" ]]; then
      hash=$(git -C "$omarchy_path" rev-parse --short HEAD 2>/dev/null || true)

      if [[ -n $hash ]]; then
        echo "dev ($hash)"
      else
        echo "dev"
      fi

      exit 0
    fi

    echo "unknown (no Arch package database on NixOS)" >&2
    exit 1
    EOF
        chmod +x bin/omarchy-version

        # omarchy-update-restart: a NixOS kernel update is a new
        # /run/current-system generation — compare it against the booted
        # one (upstream probes kernel files with pacman -Qo, which on
        # NixOS would report "kernel updated" after EVERY update).
        cat >bin/omarchy-update-restart <<'EOF'
    #!/bin/bash
    # omarchy:summary=Prompt for required reboot or service restarts after updates

    echo

    confirm_reboot() {
      gum confirm "$1" && { omarchy-system-reboot; exit 0; }
    }

    # omarchy-nix: generation-based kernel check (no pacman).
    kernel_updated=false

    if [[ -e /run/booted-system/kernel && -e /run/current-system/kernel ]]; then
      if [[ $(readlink -f /run/booted-system/kernel) != $(readlink -f /run/current-system/kernel) ]]; then
        kernel_updated=true
      fi
    fi

    if [[ $kernel_updated == "true" ]]; then
      confirm_reboot "Linux kernel has been updated. Reboot?"
    elif [[ -f $HOME/.local/state/omarchy/reboot-required ]]; then
      confirm_reboot "Updates require reboot. Ready?"
    fi

    running_hyprland=$(readlink /proc/$(pgrep -x Hyprland)/exe 2>/dev/null)
    if [[ $running_hyprland == *"(deleted)"* ]]; then
      confirm_reboot "Hyprland has been updated. Reboot?"
    fi

    for file in "$HOME"/.local/state/omarchy/restart-*-required; do
      if [[ -f $file ]]; then
        filename=$(basename "$file")
        service=$(echo "$filename" | sed 's/restart-\(.*\)-required/\1/')
        echo "Restarting $service"
        omarchy-state clear "$filename"
        omarchy-restart-"$service"
      fi
    done
    EOF
        chmod +x bin/omarchy-update-restart

        # omarchy-debug / omarchy-upload-log: read-only diagnostics; replace
        # the pacman -Q probes with NixOS-native equivalents.
        substituteInPlace bin/omarchy-debug \
          --replace-fail 'Omarchy Package: $(pacman -Q omarchy-dev 2>/dev/null || pacman -Q omarchy 2>/dev/null || echo "unknown")' \
                         'Omarchy Package: $(omarchy-version 2>/dev/null || echo "unknown")' \
          --replace-fail "\$({ expac -S '%n %v (%r)' \$(pacman -Qqe) 2>/dev/null; comm -13 <(pacman -Sql | sort) <(pacman -Qqe | sort) | xargs -r expac -Q '%n %v (AUR)'; } | sort)" \
                         "\$(ls /run/current-system/sw/bin 2>/dev/null | sort || echo unavailable)"

        substituteInPlace bin/omarchy-upload-log \
          --replace-fail 'echo "INSTALLED PACKAGES (pacman -Q)"' \
                         'echo "INSTALLED PACKAGES (/run/current-system/sw/bin)"' \
          --replace-fail 'pacman -Q 2>/dev/null || echo "Failed to get package list"' \
                         'ls /run/current-system/sw/bin 2>/dev/null | sort || echo "Failed to get package list"'

        # omarchy-theme-set-browser: browser accent-color policy files live
        # under /etc (module-owned on NixOS). Silent no-op — omarchy-theme-set
        # calls it on every theme change, so it must not print a stub note.
        cat >bin/omarchy-theme-set-browser <<'EOF'
    #!/bin/bash
    # omarchy:summary=Apply the current theme color to Chromium, Chrome, Edge, and Brave
    # omarchy:hidden=true
    #
    # omarchy-nix: upstream writes managed-policy color.json files
    # under browser policy dirs in /etc — on NixOS those are owned by the
    # module system (programs.chromium.policies / environment.etc), so runtime
    # policy writes are impossible and the browser accent color does not
    # follow the theme. Silent no-op: called by omarchy-theme-set.
    exit 0
    EOF
        chmod +x bin/omarchy-theme-set-browser

        # omarchy-install-dev-env: drop the /etc/php mutations from the PHP
        # flow (php.ini + xdebug.ini are declarative on NixOS); the mise-based
        # per-user toolchain install and the Composer PATH setup stay.
        # Anchors are verified and deleted as an explicit line range (no open
        # `,+Nd` patterns) so an upstream restructure fails the build instead
        # of silently deleting unrelated user-state logic.
        {
          dev_env=bin/omarchy-install-dev-env
          # Fixed-string anchors (unique within install_php); fail-closed.
          for pat in \
            '  # Enable some extensions' \
            'local php_ini_path="/etc/php/php.ini"' \
            'local extensions_to_enable=(' \
            '  # Enable Xdebug' \
            'for ext in "''${extensions_to_enable[@]}"' \
            '/etc/php/conf.d/xdebug.ini'
          do
            grep -qF "$pat" "$dev_env" || {
              echo "omarchy-install-dev-env: expected PHP-mutation anchor missing: $pat" >&2
              exit 1
            }
          done
          start=$(grep -nF '  # Enable some extensions' "$dev_env" | head -1 | cut -d: -f1)
          # The for-ext loop's closing `done` is the last line of the block.
          end=$(awk -v s="$start" 'NR > s && /^  done$/ { print NR; exit }' "$dev_env")
          if [[ -z "$start" || -z "$end" || "$end" -le "$start" ]]; then
            echo "omarchy-install-dev-env: could not resolve PHP-mutation line range (start=$start end=$end)" >&2
            exit 1
          fi
          sed -i "''${start},''${end}d" "$dev_env"
        }
        substituteInPlace bin/omarchy-install-dev-env \
          --replace-fail \
            $'install_php() {\n  omarchy-pkg-add' \
            $'install_php() {\n  echo "NixOS: PHP extensions and php.ini are declarative (php.buildEnv / devshell); nothing is written under /etc."\n  omarchy-pkg-add'

        # Menu: delete entries whose only implementation is an Arch
        # system mutation (the scripts behind them are stubbed above; ids are
        # manifest-driven). sed-line deletion is glyph-safe (upstream icons are
        # multibyte); the grep guard fails the build when upstream renames an
        # entry, i.e. this patch is stale.
        for id in ${lib.concatStringsSep " " runtimeManifest.hiddenMenuIds}; do
          grep -q "^  \"$id\":" default/omarchy/omarchy-menu.jsonc ||
            { echo "omarchy-menu.jsonc: expected entry missing (stale patch): $id"; exit 1; }
          sed -i "/^  \"$id\":/d" default/omarchy/omarchy-menu.jsonc
        done

        # Xbox controllers get a real NixOS implementation instead: the
        # hardware.xpadneo catalog feature (B19 rewire machinery).
        substituteInPlace default/omarchy/omarchy-menu.jsonc \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-xbox-controllers" \
                         "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.xbox-controllers'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-xbox-controllers" \
                         "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.xbox-controllers'"

        # Presence guards: consult nix-catalog.json — present
        # when the entry is in omarchy-packages.json OR a declared binary is
        # on PATH (installed by hand in the consumer config). Unknown names
        # fall back to a plain command -v probe. Conditional pacman install
        # paths in upstream scripts still route into the declarative stubs: the
        # scripts call omarchy-pkg-missing (kept: always exit 0) to proceed.
        cat > bin/omarchy-pkg-present <<'EOF'
    #!/bin/bash
    # omarchy-nix: presence probe for menu `when:` guards.
    # Exit 0 when the entry is managed (in omarchy-packages.json) or its binary
    # is on PATH; exit 1 otherwise.
    set -u

    name="''${1:-}"
    [[ -n $name ]] || exit 1

    OMARCHY_PATH="''${OMARCHY_PATH:-/run/current-system/sw/share/omarchy}"
    catalog="$OMARCHY_PATH/nix-catalog.json"
    [[ -f $catalog ]] || { command -v "$name" >/dev/null 2>&1; exit $?; }

    # Shared OMARCHY_NIX_FLAKE resolver — presence checks observe
    # the same JSON location that add/remove/update mutate. An invalid
    # explicit value fails closed: diagnostics on stderr, never a fallback to
    # another checkout (the binary probe below is unchanged).
    source "$(dirname "''${BASH_SOURCE[0]}")/omarchy-nix-pkglib"

    resolve_json() {
      local d rc=0
      d=$(resolve_flake_dir) || rc=$?
      ((rc == 0)) || return 1
      [[ -f $d/omarchy-packages.json ]] || return 1
      printf '%s\n' "$d/omarchy-packages.json"
    }

    entry=$(jq -c --arg a "$name" '[.entries | to_entries[] | select(.value.arch == $a) | .value] | first // empty' "$catalog" 2>/dev/null || true)

    if [[ -n $entry ]]; then
      json_path=$(resolve_json || true)
      if [[ -n ''${json_path:-} ]]; then
        while read -r p; do
          [[ -n $p ]] || continue
          jq -e --arg p "$p" '.packages // [] | index($p)' "$json_path" >/dev/null 2>&1 && exit 0
        done < <(jq -r '.pkgs // [] | .[]' <<<"$entry")
        f=$(jq -r '.feature // ""' <<<"$entry")
        if [[ -n $f ]] && jq -e --arg f "$f" '.features // [] | index($f)' "$json_path" >/dev/null 2>&1; then
          exit 0
        fi
      fi
      while read -r b; do
        [[ -n $b ]] && command -v "$b" >/dev/null 2>&1 && exit 0
      done < <(jq -r '.binaries // [] | .[]' <<<"$entry")
      exit 1
    fi

    # Alias entries (arch names that only need a binary probe, e.g. voxtype-bin).
    alias_bins=$(jq -r --arg a "$name" '.aliases[$a].binaries // [] | .[]' "$catalog" 2>/dev/null || true)
    if [[ -n $alias_bins ]]; then
      while read -r b; do
        [[ -n $b ]] && command -v "$b" >/dev/null 2>&1 && exit 0
      done <<<"$alias_bins"
      exit 1
    fi

    # Fallback: treat the argument as a plain binary name.
    command -v "$name" >/dev/null 2>&1
    EOF
        chmod +x bin/omarchy-pkg-present

        cat > bin/omarchy-pkg-missing <<'EOF'
    #!/bin/bash
    # omarchy-nix: always report "missing" so pkg-add stubs run (and print).
    exit 0
    EOF
        chmod +x bin/omarchy-pkg-missing

        # Channel query used by the Update → Channel menu checkmarks.
        cat > bin/omarchy-channel-current <<'EOF'
    #!/bin/bash
    # omarchy-nix: no pacman channel; report a stable label for the UI.
    echo nixos
    exit 0
    EOF
        chmod +x bin/omarchy-channel-current

        # Update-available drives the shell status indicator. On NixOS there is
        # no pacman checkupdates path; exit non-zero so the bar clears the
        # indicator instead of showing a stale "updates available".
        cat > bin/omarchy-update-available <<'EOF'
    #!/bin/bash
    # omarchy-nix: no pacman update probe. Exit non-zero so the shell clears
    # the update indicator. Verbose when stdout is a TTY or -v is passed.
    if [[ -t 1 || ''${1:-} == "-v" || ''${1:-} == "--verbose" ]]; then
      echo "NixOS: omarchy-update-available has no pacman probe."
      echo "Use Update → Omarchy (omarchy-update) to flake-update + rebuild,"
      echo "or manage the system with nixos-rebuild directly."
    fi
    exit 1
    EOF
        chmod +x bin/omarchy-update-available

        # Point the failure trap at the full log (issue #55): the
        # presentation window closes on any key (omarchy-show-done), so the
        # error text vanishes with it. omarchy-update already tees everything
        # through `script` into /tmp/omarchy-update.log — say so in the trap
        # message and closing the window stops being destructive.
        substituteInPlace bin/omarchy-update \
          --replace-fail \
            'correct the error, and retry the update.\n\nIf you need assistance' \
            'correct the error, and retry the update.\n\nFull log: /tmp/omarchy-update.log\n\nIf you need assistance'

        # Snapshot: snapper/limine are Arch. Exit 0 with a note so
        # `omarchy-snapshot create || (($? == 127))` in omarchy-update
        # continues (exit 0 also satisfies the || chain).
        cat > bin/omarchy-snapshot <<'EOF'
    #!/bin/bash
    # omarchy-nix: snapper/limine snapshots are Arch-only.

    COMMAND="''${1:-}"

    if [[ -z $COMMAND ]]; then
      echo "Usage: omarchy-snapshot <create|restore>" >&2
      exit 1
    fi

    case "$COMMAND" in
    create)
      echo -e "\e[33mNixOS: skipping snapper snapshot.\e[0m"
      echo "NixOS rollbacks use boot generations:"
      echo "  sudo nixos-rebuild list-generations"
      echo "  (or pick a previous generation at the boot menu)"
      echo
      exit 0
      ;;
    restore)
      echo "NixOS: use 'sudo nixos-rebuild list-generations' / boot menu to roll back."
      exit 0
      ;;
    *)
      echo "Usage: omarchy-snapshot <create|restore>" >&2
      exit 1
      ;;
    esac
    EOF
        chmod +x bin/omarchy-snapshot

        # Package-refresh core of omarchy-update: NixOS-native flake update +
        # nixos-rebuild. Resolve the consumer flake, then refresh inputs and
        # switch. DRY-RUN and rebuild-cmd env vars support tests.
        cat > bin/omarchy-update-system-pkgs <<'EOF'
    #!/bin/bash
    # omarchy-nix: NixOS-native system package refresh.

    set -e

    # Shared OMARCHY_NIX_FLAKE resolver: accepts a flake
    # directory or the flake.nix file itself; an explicit-but-invalid value
    # fails closed instead of falling back to another checkout.
    source "$(dirname "''${BASH_SOURCE[0]}")/omarchy-nix-pkglib"

    echo -e "\e[32m\nUpdate system (NixOS)\e[0m"

    rc=0
    flake_dir=$(resolve_flake_dir) || rc=$?
    if ((rc == 2)); then
      echo -e "\e[31mInvalid OMARCHY_NIX_FLAKE (see above) — fix or unset it.\e[0m" >&2
      exit 1
    elif ((rc != 0)); then
      cat <<'MSG'
    NixOS: no consumer flake found for omarchy-update.

    Set OMARCHY_NIX_FLAKE to your config flake directory (or its flake.nix
    file), or place a flake providing nixosConfigurations for this host at:
      ~/omarchy-nix/
      ~/Projects/omarchy-nix/
      /etc/nixos/

    Packages and the system are declarative on NixOS — manage them in your flake
    and run nixos-rebuild switch there. Skipping package refresh.
    MSG
      exit 0
    fi

    echo "Using flake: $flake_dir"

    run_or_print() {
      if [[ ''${OMARCHY_NIX_UPDATE_DRY_RUN:-} == 1 ]]; then
        printf 'DRY-RUN:'
        printf ' %q' "$@"
        printf '\n'
      else
        "$@"
      fi
    }

    rebuild_cmd="''${OMARCHY_NIX_REBUILD_CMD:-switch}"

    # The setuid sudo wrapper (/run/wrappers/bin/sudo) is provided by the
    # sourced omarchy-nix-pkglib.

    if [[ ''${OMARCHY_NIX_SKIP_FLAKE_UPDATE:-} == 1 ]]; then
      echo "Skipping nix flake update (OMARCHY_NIX_SKIP_FLAKE_UPDATE=1)"
    elif [[ -w $flake_dir/flake.lock ]] || [[ ! -e $flake_dir/flake.lock && -w $flake_dir ]]; then
      run_or_print nix flake update --flake "$flake_dir"
    else
      # Root-owned consumer flake (typical /etc/nixos): the user cannot write
      # flake.lock, so a plain `nix flake update` would fail and abort the
      # pipeline. Same sudo path as the rebuild below.
      run_or_print sudo nix flake update --flake "$flake_dir"
    fi
    run_or_print sudo nixos-rebuild "$rebuild_cmd" --flake "$flake_dir"
    echo
    EOF
        chmod +x bin/omarchy-update-system-pkgs

        # Firmware update keeps fwupdmgr (works on NixOS). Drop the pacman
        # install helper — fwupd is provided by services.fwupd + runtimeDeps —
        # and the ESP staging copy (NixOS manages the ESP declaratively).
        substituteInPlace bin/omarchy-update-firmware \
          --replace-fail \
            $'if omarchy-cmd-missing fwupdmgr; then\n  omarchy-pkg-add fwupd\nfi\n\n' \
            $'if omarchy-cmd-missing fwupdmgr; then\n  echo "NixOS: fwupdmgr not found. Enable services.fwupd.enable (omarchy module default) and rebuild."\n  exit 1\nfi\n\n' \
          --replace-fail \
            $'if [[ -d /sys/firmware/efi ]] && [[ -f /usr/lib/fwupd/efi/fwupdx64.efi ]]; then\n  sudo install -D /usr/lib/fwupd/efi/fwupdx64.efi /boot/EFI/arch/fwupdx64.efi\nfi\n\n' \
            $'# omarchy-nix: upstream stages fwupdx64.efi on the ESP here;\n# the ESP is managed declaratively on NixOS (services.fwupd / boot.loader).\n\n'

        # Migrations: full NixOS-aware rewrite of omarchy-migrate.
        # Upstream's runner is pacman-coupled (db.lck wait) and ran every
        # historical script blindly; ours is fail-closed: every vendored
        # migration must be classified in migrations-nix.json (enforced by
        # checks.omarchy-migrations), a failure is NOT marked done and fails
        # the run, and the first run on a fresh install baselines the whole
        # vendored set instead of replaying Arch migration history. Class
        # "adapter" runs a NixOS replacement from $OMARCHY_PATH/migrations-nix/
        # (installed from pkgs/migrations-nix/ below) instead of the vendored
        # script.
        cat > bin/omarchy-migrate <<'EOF'
    #!/bin/bash
    # omarchy-nix: NixOS-aware, fail-closed migration runner.
    #
    # Differences from upstream omarchy-migrate:
    #   - no pacman lock wait (there is no pacman on NixOS);
    #   - every vendored migration must be classified in migrations-nix.json
    #     (skip / user-safe / adapter — enforced by checks.omarchy-migrations);
    #   - "adapter" runs the NixOS replacement from migrations-nix/ instead of
    #     the vendored script;
    #   - first run baselines: a fresh NixOS install has no Arch history to
    #     replay, so all vendored migrations are marked applied at once;
    #   - a failed migration is NOT marked, retries on the next run, and fails
    #     this run (exit 1) after the rest of the queue has been attempted;
    #   - OMARCHY_NIX_UPDATE_DRY_RUN=1 reports without mutating anything.

    set -euo pipefail

    mode="run"

    usage() {
      echo "Usage: omarchy-migrate [--pending]"
    }

    while (($#)); do
      case "$1" in
        --pending|--check)
          mode="pending"
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
      esac
    done

    OMARCHY_PATH="''${OMARCHY_PATH:-/usr/share/omarchy}"
    STATE_DIR="''${OMARCHY_MIGRATION_STATE:-$HOME/.local/state/omarchy/migrations}"
    MIGRATIONS_DIR="$OMARCHY_PATH/migrations"
    ADAPTERS_DIR="$OMARCHY_PATH/migrations-nix"
    MANIFEST="$OMARCHY_PATH/migrations-nix.json"
    DRY_RUN="''${OMARCHY_NIX_UPDATE_DRY_RUN:-}"

    migration_entries() {
      [[ -d $MIGRATIONS_DIR ]] || return 0

      local file filename

      for file in "$MIGRATIONS_DIR"/*.sh; do
        [[ -f $file ]] || continue
        filename=$(basename "$file")
        printf '%s\t%s\t%s\n' "$filename" "$file" "$STATE_DIR/$filename"
      done
    }

    pending_migrations() {
      local name file marker

      while IFS=$'\t' read -r name file marker; do
        [[ -n $name ]] || continue
        if [[ ! -f $marker ]]; then
          printf '%s\n' "$name"
        fi
      done < <(migration_entries)
    }

    # An unseeded state dir means a fresh NixOS user, and a fresh NixOS user
    # has no Arch migration history to replay: the vendored set IS the
    # baseline. --pending stays read-only and reports this as "nothing
    # pending"; the first real run writes every marker at once instead of
    # executing 40+ migrations written for machines that were never NixOS.
    if [[ ! -d $STATE_DIR ]]; then
      if [[ $mode == "pending" ]]; then
        exit 1
      fi

      if [[ $DRY_RUN == 1 ]]; then
        echo "DRY-RUN: would baseline all vendored migrations in $STATE_DIR"
      else
        echo "First migration run on NixOS: baselining all vendored migrations as applied."
        while IFS=$'\t' read -r name file marker; do
          [[ -n $name ]] || continue
          mkdir -p "$(dirname "$marker")"
          touch "$marker"
        done < <(migration_entries)
      fi
      exit 0
    fi

    if [[ $mode == "pending" ]]; then
      pending_output=$(pending_migrations)
      if [[ -n $pending_output ]]; then
        printf '%s\n' "$pending_output"
        exit 0
      fi
      exit 1
    fi

    [[ -d $MIGRATIONS_DIR ]] || exit 0

    if [[ ! -f $MANIFEST ]]; then
      echo "omarchy-migrate: $MANIFEST not found (broken omarchy-nix package)" >&2
      exit 1
    fi

    declare -A MIGRATION_CLASS=()
    while IFS=$'\t' read -r class_key class_value; do
      MIGRATION_CLASS[$class_key]=$class_value
    done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$MANIFEST")

    mkdir -p "$STATE_DIR"

    failed=0

    run_migration() {
      local name="$1" script="$2" marker="$3"

      echo -e "\e[32m\nRunning migration (''${name%.sh})\e[0m"

      if [[ $DRY_RUN == 1 ]]; then
        echo "DRY-RUN: would run $script and mark $name as applied"
        return 0
      fi

      if OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$script"; then
        touch "$marker"
      else
        echo -e "\e[31mMigration ''${name%.sh} failed — NOT marked as applied; it will be retried on the next run.\e[0m" >&2
        failed=1
      fi
    }

    while IFS=$'\t' read -r name file marker; do
      [[ -n $name ]] || continue
      [[ -f $marker ]] && continue

      class="''${MIGRATION_CLASS[$name]:-}"

      case "$class" in
        skip)
          echo -e "\e[33mSkipping NixOS-exempt migration (''${name%.sh})\e[0m"
          if [[ $DRY_RUN == 1 ]]; then
            echo "DRY-RUN: would mark $name as applied"
          else
            touch "$marker"
          fi
          ;;
        user-safe)
          run_migration "$name" "$file" "$marker"
          ;;
        adapter)
          adapter="$ADAPTERS_DIR/$name"
          if [[ -f $adapter ]]; then
            run_migration "$name" "$adapter" "$marker"
          else
            echo -e "\e[31momarchy-migrate: no adapter file for $name ($adapter missing)\e[0m" >&2
            failed=1
          fi
          ;;
        *)
          echo -e "\e[31momarchy-migrate: $name is not classified in migrations-nix.json — refusing to run it\e[0m" >&2
          echo "Classify it in pkgs/omarchy-migrations.nix and rebuild the omarchy package." >&2
          failed=1
          ;;
      esac
    done < <(migration_entries)

    # Clear a login-time notification the user left sitting there and then
    # resolved by running migrations some other way. The substring matches
    # both the current and legacy notification titles.
    if [[ $DRY_RUN != 1 ]]; then
      omarchy-notification-dismiss "Omarchy Migrations" >/dev/null 2>&1 || true
    fi

    if (( failed )); then
      echo "omarchy-migrate: one or more migrations failed (see above) — failing the run so the problem is not silently buried." >&2
      exit 1
    fi
    EOF
        chmod +x bin/omarchy-migrate

        # Dry-run must only report: skip the post-update hook there (hooks can
        # mutate user state). Migrations handle their own dry-run internally.
        substituteInPlace bin/omarchy-update \
          --replace-fail \
            $'  omarchy-migrate\n  omarchy-hook post-update\n' \
            $'  omarchy-migrate\n  if [[ ''${OMARCHY_NIX_UPDATE_DRY_RUN:-} != 1 ]]; then\n    omarchy-hook post-update\n  fi\n'

        # Menu: Install Package / Remove Package → nix-native flows; the AUR
        # entry is deleted outright (no AUR analogue on NixOS — a dead item
        # showing only a note is clutter). Line content replaced with "" so
        # --replace-fail still breaks the build loudly if upstream renames it.
        substituteInPlace default/omarchy/omarchy-menu.jsonc \
          --replace-fail \
            '"install.package": {"icon":"󰣇","label":"Package","action":"xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install"}' \
            '"install.package": {"icon":"󰣇","label":"Package","action":"omarchy-launch-floating-terminal-with-presentation omarchy-nix-search"}' \
          --replace-fail \
            '  "install.aur": {"icon":"󰣇","label":"AUR","action":"xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-aur-install"},' \
            "" \
          --replace-fail \
            '"remove.package": {"icon":"󰣇","label":"Package","action":"xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-remove"}' \
            '"remove.package": {"icon":"󰣇","label":"Package","action":"omarchy-launch-floating-terminal-with-presentation omarchy-nix-remove"}'

        # Menu rewiring: cataloged entries call omarchy-nix-add /
        # omarchy-nix-remove. Action-part-only substitutions (glyph-free), so
        # upstream `when:` guards and icons stay untouched. Development entries
        # additionally replace their mise-dir guards with pkg-present probes.
        # NordVPN and ONCE lines are deleted outright (same rule as
        # install.aur): ONCE is AUR-only, and NordVPN's nixpkgs package +
        # services.nordvpn module landed only in the 26.11 cycle — re-add as
        # a catalog feature once our stable pin catches up.
        substituteInPlace default/omarchy/omarchy-menu.jsonc \
          --replace-fail "'omarchy-install-browser chrome'" "'omarchy-nix-add install.browser.chrome'" \
          --replace-fail "'omarchy-install-browser edge'" "'omarchy-nix-add install.browser.edge'" \
          --replace-fail "'omarchy-install-browser brave'" "'omarchy-nix-add install.browser.brave'" \
          --replace-fail "'omarchy-install-browser firefox'" "'omarchy-nix-add install.browser.firefox'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-1password" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.1password'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-dropbox" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.dropbox'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-spotify" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.spotify'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-signal" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.signal'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-tailscale" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.tailscale'" \
          --replace-fail '  "install.service.nordvpn": {"icon":"󱇱","label":"NordVPN [AUR]","when":"! omarchy-pkg-present nordvpn-bin","action":"omarchy-launch-floating-terminal-with-presentation omarchy-install-service-nordvpn"},' "" \
          --replace-fail '  "install.service.once": {"icon":"󰏖","label":"ONCE","when":"! omarchy-pkg-present once-bin","action":"omarchy-launch-floating-terminal-with-presentation omarchy-install-service-once"},' "" \
          --replace-fail "omarchy-install-and-launch Bitwarden 'bitwarden bitwarden-cli' bitwarden" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.service.bitwarden'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-editor-vscode" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.vscode'" \
          --replace-fail "omarchy-install-and-launch Cursor cursor-bin cursor" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.cursor'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-editor-zed" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.zed'" \
          --replace-fail "omarchy-install-and-launch 'Sublime Text' sublime-text-4 sublime_text" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.sublime'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-editor-helix" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.helix'" \
          --replace-fail "omarchy-install-app Vim vim" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.vim'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-editor-emacs" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.editor.emacs'" \
          --replace-fail "'omarchy-install-terminal alacritty'" "'omarchy-nix-add install.terminal.alacritty'" \
          --replace-fail "'omarchy-install-terminal foot'" "'omarchy-nix-add install.terminal.foot'" \
          --replace-fail "'omarchy-install-terminal ghostty'" "'omarchy-nix-add install.terminal.ghostty'" \
          --replace-fail "'omarchy-install-terminal kitty'" "'omarchy-nix-add install.terminal.kitty'" \
          --replace-fail "omarchy-install-app 'LM Studio' lmstudio-bin" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.lm-studio'" \
          --replace-fail 'if omarchy-cmd-present nvidia-smi; then ollama_pkg=ollama-cuda; elif omarchy-cmd-present rocminfo; then ollama_pkg=ollama-rocm; else ollama_pkg=ollama; fi; omarchy-install-app Ollama \"$ollama_pkg\"' "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.ai.ollama'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-steam" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.steam'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-retroarch" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.retroarch'" \
          --replace-fail "omarchy-install-and-launch Minecraft minecraft-launcher minecraft-launcher" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.minecraft'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-heroic" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.heroic'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-install-gaming-lutris" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-add install.gaming.lutris'" \
          --replace-fail "'omarchy-install-dev-env ruby'" "'omarchy-nix-add install.development.rails'" \
          --replace-fail "'omarchy-install-dev-env go'" "'omarchy-nix-add install.development.go'" \
          --replace-fail "'omarchy-install-dev-env python'" "'omarchy-nix-add install.development.python'" \
          --replace-fail "'omarchy-install-dev-env zig'" "'omarchy-nix-add install.development.zig'" \
          --replace-fail "'omarchy-install-dev-env rust'" "'omarchy-nix-add install.development.rust'" \
          --replace-fail "'omarchy-install-dev-env java'" "'omarchy-nix-add install.development.java'" \
          --replace-fail "'omarchy-install-dev-env dotnet'" "'omarchy-nix-add install.development.dotnet'" \
          --replace-fail "'omarchy-install-dev-env ocaml'" "'omarchy-nix-add install.development.ocaml'" \
          --replace-fail "'omarchy-install-dev-env clojure'" "'omarchy-nix-add install.development.clojure'" \
          --replace-fail "'omarchy-install-dev-env scala'" "'omarchy-nix-add install.development.scala'" \
          --replace-fail "'omarchy-install-dev-env node'" "'omarchy-nix-add install.development.javascript.node'" \
          --replace-fail "'omarchy-install-dev-env bun'" "'omarchy-nix-add install.development.javascript.bun'" \
          --replace-fail "'omarchy-install-dev-env deno'" "'omarchy-nix-add install.development.javascript.deno'" \
          --replace-fail "'omarchy-install-dev-env php'" "'omarchy-nix-add install.development.php.php'" \
          --replace-fail "'omarchy-install-dev-env elixir'" "'omarchy-nix-add install.development.elixir.elixir'" \
          --replace-fail "'omarchy-install-dev-env laravel'" "omarchy-nix-declarative-note" \
          --replace-fail "'omarchy-install-dev-env symfony'" "omarchy-nix-declarative-note" \
          --replace-fail "'omarchy-install-dev-env phoenix'" "omarchy-nix-declarative-note" \
          --replace-fail "'omarchy-remove-browser chrome'" "'omarchy-nix-remove install.browser.chrome'" \
          --replace-fail "'omarchy-remove-browser edge'" "'omarchy-nix-remove install.browser.edge'" \
          --replace-fail "'omarchy-remove-browser brave'" "'omarchy-nix-remove install.browser.brave'" \
          --replace-fail "'omarchy-remove-browser firefox'" "'omarchy-nix-remove install.browser.firefox'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-service-dropbox" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.service.dropbox'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-service-tailscale" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.service.tailscale'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-steam" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.steam'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-retroarch" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.retroarch'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-minecraft" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.minecraft'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-heroic" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.heroic'" \
          --replace-fail "omarchy-launch-floating-terminal-with-presentation omarchy-remove-gaming-lutris" "omarchy-launch-floating-terminal-with-presentation 'omarchy-nix-remove install.gaming.lutris'" \
          --replace-fail "'omarchy-remove-dev-env ruby'" "'omarchy-nix-remove install.development.rails'" \
          --replace-fail "'omarchy-remove-dev-env go'" "'omarchy-nix-remove install.development.go'" \
          --replace-fail "'omarchy-remove-dev-env python'" "'omarchy-nix-remove install.development.python'" \
          --replace-fail "'omarchy-remove-dev-env zig'" "'omarchy-nix-remove install.development.zig'" \
          --replace-fail "'omarchy-remove-dev-env rust'" "'omarchy-nix-remove install.development.rust'" \
          --replace-fail "'omarchy-remove-dev-env java'" "'omarchy-nix-remove install.development.java'" \
          --replace-fail "'omarchy-remove-dev-env dotnet'" "'omarchy-nix-remove install.development.dotnet'" \
          --replace-fail "'omarchy-remove-dev-env ocaml'" "'omarchy-nix-remove install.development.ocaml'" \
          --replace-fail "'omarchy-remove-dev-env clojure'" "'omarchy-nix-remove install.development.clojure'" \
          --replace-fail "'omarchy-remove-dev-env scala'" "'omarchy-nix-remove install.development.scala'" \
          --replace-fail "'omarchy-remove-dev-env node'" "'omarchy-nix-remove install.development.javascript.node'" \
          --replace-fail "'omarchy-remove-dev-env bun'" "'omarchy-nix-remove install.development.javascript.bun'" \
          --replace-fail "'omarchy-remove-dev-env deno'" "'omarchy-nix-remove install.development.javascript.deno'" \
          --replace-fail "'omarchy-remove-dev-env php'" "'omarchy-nix-remove install.development.php.php'" \
          --replace-fail "'omarchy-remove-dev-env elixir'" "'omarchy-nix-remove install.development.elixir.elixir'" \
          --replace-fail "'omarchy-remove-dev-env laravel'" "omarchy-nix-declarative-note" \
          --replace-fail "'omarchy-remove-dev-env symfony'" "omarchy-nix-declarative-note" \
          --replace-fail "'omarchy-remove-dev-env phoenix'" "omarchy-nix-declarative-note"

        # Development entries: replace mise-dir / rustup / opam guards with
        # pkg-present probes (php's guard is already pkg-present upstream).
        # Install side uses the negated form; remove side uses the positive form.
        substituteInPlace default/omarchy/omarchy-menu.jsonc \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/ruby ]]' '! omarchy-pkg-present ruby' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/go ]]' '! omarchy-pkg-present go' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/python ]]' '! omarchy-pkg-present python' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/zig ]]' '! omarchy-pkg-present zig' \
          --replace-fail '[[ ! -d $HOME/.rustup ]]' '! omarchy-pkg-present rust' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/java ]]' '! omarchy-pkg-present java' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/dotnet ]]' '! omarchy-pkg-present dotnet' \
          --replace-fail '[[ ! -d $HOME/.opam ]]' '! omarchy-pkg-present ocaml' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/clojure ]]' '! omarchy-pkg-present clojure' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/scala ]]' '! omarchy-pkg-present scala' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/node ]]' '! omarchy-pkg-present node' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/bun ]]' '! omarchy-pkg-present bun' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/deno ]]' '! omarchy-pkg-present deno' \
          --replace-fail '[[ ! -d $HOME/.local/share/mise/installs/elixir ]]' '! omarchy-pkg-present elixir' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/ruby ]]' 'omarchy-pkg-present ruby' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/go ]]' 'omarchy-pkg-present go' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/python ]]' 'omarchy-pkg-present python' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/zig ]]' 'omarchy-pkg-present zig' \
          --replace-fail '[[ -d $HOME/.rustup ]]' 'omarchy-pkg-present rust' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/java ]]' 'omarchy-pkg-present java' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/dotnet ]]' 'omarchy-pkg-present dotnet' \
          --replace-fail '[[ -d $HOME/.opam ]]' 'omarchy-pkg-present ocaml' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/clojure ]]' 'omarchy-pkg-present clojure' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/scala ]]' 'omarchy-pkg-present scala' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/node ]]' 'omarchy-pkg-present node' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/bun ]]' 'omarchy-pkg-present bun' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/deno ]]' 'omarchy-pkg-present deno' \
          --replace-fail '[[ -d $HOME/.local/share/mise/installs/elixir ]]' 'omarchy-pkg-present elixir'

        # omp (oh-my-pi) is not in nixpkgs — drop its default-agent menu
        # entry (grep guard keeps this fail-closed, like --replace-fail).
        grep -q '"setup.default.agent.omp":' default/omarchy/omarchy-menu.jsonc
        sed -i '/"setup.default.agent.omp":/d' default/omarchy/omarchy-menu.jsonc

        # Install > AI entries for the selectable default agents (Setup >
        # Defaults > Agent). Upstream lazy-installs agents via mise and needs
        # no menu entries (it also dropped install.ai.crush); the nix catalog
        # model requires one menu entry per catalog id. The lines live in
        # agentMenuEntries (let) and are inserted after the ollama entry
        # (grep guard keeps this fail-closed, like --replace-fail).
        # Pre-insert: fail if upstream already ships any of the keys we insert
        # (duplicate-key protection; install.ai.ollama / install.ai.lm-studio
        # are upstream-owned and not in this list).
        for key in \
          install.ai.claude \
          install.ai.codex \
          install.ai.copilot \
          install.ai.crush \
          install.ai.gemini \
          install.ai.grok \
          install.ai.opencode \
          install.ai.pi
        do
          if grep -q "\"$key\":" default/omarchy/omarchy-menu.jsonc; then
            echo "omarchy-menu.jsonc: $key already present (duplicate insert)" >&2
            exit 1
          fi
        done
        grep -q '"install.ai.ollama":' default/omarchy/omarchy-menu.jsonc
        sed -i '/"install.ai.ollama":/r ${agentMenuEntries}' default/omarchy/omarchy-menu.jsonc

        # omarchy-default-agent: upstream lazy-installs agents with
        # `mise use -g`; mise-fetched prebuilt binaries don't run on NixOS, so
        # route installation through the nix catalog instead. Probe the PATH
        # (an agent installed via the catalog or by hand counts), send missing
        # agents to Menu > Install > AI, and only write the default once the
        # binary exists.
        substituteInPlace bin/omarchy-default-agent \
          --replace-fail 'if [[ $installing == "false" ]] && ! mise where "$agent_package" &>/dev/null; then' \
                         'if [[ $installing == "false" ]] && omarchy-cmd-missing "$agent"; then' \
          --replace-fail 'exec omarchy-launch-floating-terminal-with-presentation omarchy-default-agent --install "$agent"' \
                         'exec omarchy-launch-floating-terminal-with-presentation "omarchy-nix-add install.ai.$agent"' \
          --replace-fail 'if ! mise use -g "$agent_package"; then' \
                         'if omarchy-cmd-missing "$agent"; then' \
          --replace-fail 'echo "Could not install $name with mise" >&2' \
                         'echo "$name is not installed — add it with Menu > Install > AI > $name." >&2' \
          --replace-fail 'echo "Could not set $name as the default coding agent" >&2' \
                         'echo "$name is not installed — add it with Menu > Install > AI > $name." >&2'
  '';

  # No configure/build step — the upstream tree is consumed as-is.
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/omarchy"
    mkdir -p "$dest"

    # Mirror the directories pacman's `omarchy` package ships under
    # /usr/share/omarchy. `cp -a` preserves modes (so the executable bit on
    # bin/omarchy-* survives) and timestamps for reproducibility.
    # install/ is required by omarchy-first-run / omarchy-finalize-user
    # (OMARCHY_INSTALL=$OMARCHY_PATH/install). applications/ is required by
    # omarchy-refresh-applications (copies *.desktop into
    # ~/.local/share/applications). Arch-only installer trees under install/
    # (packaging, login, post-install, hardware/* system-level) are unused on
    # NixOS but harmless to ship; first-run only sources install/user/.
    # etc/ is upstream's Arch /etc overlay (ISO copies it to /etc). On NixOS
    # the module declares the equivalents natively; the few drop-ins without
    # a clean native option plus the fastfetch seed take .source straight
    # from here, verbatim upstream, refreshed with every omarchy-src bump.
    # See pkgs/omarchy-etc-manifest.nix for the per-file classification.
    cp -a default bin shell themes config migrations install applications etc "$dest/"

    # B21: the upstream skill is Arch-specific (/usr/share/omarchy,
    # pacman/AUR, Arch package lifecycle). Replace it with the omarchy-nix
    # end-user skill at package build time. Upstream finalize-user still owns
    # the installation mechanism and links this exact directory into each
    # supported agent; keeping the replacement inside $OMARCHY_PATH also
    # means an upstream refresh cannot reinstall the incompatible variant.
    rm -rf "$dest/default/omarchy-skill"
    install -Dm644 ${../skills/omarchy/SKILL.md} \
      "$dest/default/omarchy-skill/SKILL.md"

    # Top-level runtime assets referenced by relative paths from within the
    # copied tree (e.g. default/chromium/extensions/copy-url/icon.png symlinks
    # to ../../../../icon.png, and chromium extension manifests resolve
    # "icon.png" relative to their own dir). Docs/license are excluded — the
    # license is already declared in meta.license below.
    cp -t "$dest/" icon.png icon.txt logo.svg logo.txt version

    # xdg-terminal-exec session default + foot's .desktop. On Arch pacman
    # installs these to /usr/share/xdg-terminal-exec/ and /usr/share/applications/;
    # we mirror them to the package's own share/ so NixOS buildEnv (see the
    # module's pathsToLink) can link them into the system profile. Without the
    # list, xdg-terminal-exec cannot resolve the session default terminal and
    # Super+Enter opens nothing; without foot.desktop the list's first entry is
    # not on the data path and the same call fails. (applications/ is also
    # vendored under share/omarchy/applications for refresh-applications.)
    install -Dm644 default/xdg-terminal-exec/hyprland-xdg-terminals.list \
      "$out/share/xdg-terminal-exec/hyprland-xdg-terminals.list"
    install -Dm644 applications/foot.desktop \
      "$out/share/applications/foot.desktop"

    # Webapp icons. The vendored applications/*.desktop reference bare icon
    # names (Icon=chatgpt, Icon=disk-usage, Icon=google-contacts, ...) whose
    # PNGs live in applications/icons/ under CamelCase / spaced filenames
    # (ChatGPT.png, "Disk Usage.png", Battle.net.png). Upstream installs them
    # to /usr/share/icons/hicolor/256x256/apps/ lowercased with spaces and
    # dots turned into hyphens (verified on the Arch reference box:
    # chatgpt.png, disk-usage.png, battle-net.png, hey.png, x.png, ...).
    # Mirror that here so the quickshell launcher resolves the icons; NixOS
    # links /share/icons into the system profile via xdg.icons.enable.
    for icon in applications/icons/*.png; do
      name=$(basename "$icon" .png)
      name=$(printf '%s' "$name" | tr 'A-Z' 'a-z' | tr ' .' '--')
      install -Dm644 "$icon" "$out/share/icons/hicolor/256x256/apps/$name.png"
    done

    # Menu Install/Remove catalog (nix-catalog.json): single source of truth
    # for omarchy-nix-add/remove, pkg-present guards, and the module's unfree
    # whitelist extension. See pkgs/omarchy-catalog.nix.
    install -Dm644 ${writeText "nix-catalog.json" (builtins.toJSON (import ./omarchy-catalog.nix))} \
      "$out/share/omarchy/nix-catalog.json"

    # Migration classification manifest + NixOS adapters:
    # migrations-nix.json is consumed by the rewritten bin/omarchy-migrate;
    # class "adapter" runs the replacement from migrations-nix/ instead of the
    # vendored script. See pkgs/omarchy-migrations.nix.
    install -Dm644 ${writeText "migrations-nix.json" (builtins.toJSON (import ./omarchy-migrations.nix))} \
      "$out/share/omarchy/migrations-nix.json"
    for adapter in ${./migrations-nix}/*.sh; do
      install -Dm755 "$adapter" "$out/share/omarchy/migrations-nix/$(basename "$adapter")"
    done

    # The omarchy icon font (menu glyphs — the "iconFont" fields in
    # omarchy-menu.jsonc). Upstream installs it to /usr/share/fonts/omarchy/;
    # mirror under the package's share/fonts so NixOS fonts.packages picks it
    # up. The companion fontconfig aliases (default/fontconfig/50-omarchy.conf)
    # are wired by the NixOS module via environment.etc.
    install -Dm644 default/fonts/omarchy/omarchy.ttf \
      "$out/share/fonts/omarchy/omarchy.ttf"

    # Path-adapted systemd user units. systemd.packages (type=user) links
    # $out/lib/systemd/user/* into /etc/systemd/user. Upstream ships them
    # under default/systemd/user/ (pacman → /usr/lib/systemd/user/).
    install -Dm644 default/systemd/user/*.service -t "$out/lib/systemd/user"
    # app.slice.d/10-oomd.conf drop-in: marks user app scopes as the only
    # systemd-oomd kill candidates (the compositor lives in session.slice).
    install -Dm644 default/systemd/user/app.slice.d/10-oomd.conf -t "$out/lib/systemd/user/app.slice.d"

    # P4: presentation helper for Install/Remove Package/AUR menu entries.
    # Lives only in the package tree (not upstream); documents declarative
    # package management so the menu does not open a useless pacman TUI.
    cat >"$dest/bin/omarchy-nix-declarative-note" <<'EOF'
    #!/bin/bash
    # omarchy-nix: menu helper for Install/Remove Package/AUR on NixOS.

    cat <<'MSG'
    NixOS: packages are declarative

    Arch Omarchy installs packages with pacman/yay. On NixOS, add packages to
    your flake configuration (environment.systemPackages or omarchy options)
    and apply with:

      nixos-rebuild switch --flake <your-flake>

    Set OMARCHY_NIX_FLAKE to your config flake so Update → Omarchy can run
    flake update + rebuild for you.
    MSG

    if (($# > 0)); then
      echo
      echo "Requested: $*"
    fi

    exit 0
    EOF
    chmod +x "$dest/bin/omarchy-nix-declarative-note"

    # omarchy-nix-pkglib: shared transaction machinery for omarchy-nix-add /
    # omarchy-nix-remove. Sourced by both scripts; deliberately NOT
    # executable (it is a library). Provides: per-JSON flock serialization
    # (held through read -> write -> rebuild -> rollback), schema validation,
    # batch mutation, unique-temp + atomic rename, hash-checked rollback, and
    # a durable per-operation audit log under $XDG_STATE_HOME/omarchy/nix-add.
    cat >"$dest/bin/omarchy-nix-pkglib" <<'EOF'
    # omarchy-nix transaction library — source, do not execute.

    OMARCHY_PATH="''${OMARCHY_PATH:-/run/current-system/sw/share/omarchy}"
    CATALOG="$OMARCHY_PATH/nix-catalog.json"
    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/nix-add"

    log() { echo -e "\e[32m$*\e[0m"; }
    warn() { echo -e "\e[33m$*\e[0m" >&2; }
    die() { echo -e "\e[31m$*\e[0m" >&2; exit 1; }

    # ONE OMARCHY_NIX_FLAKE resolver for every omarchy-nix command.
    # Accepted explicit forms: a directory containing flake.nix, or
    # the path to the flake.nix file itself. An explicit-but-invalid value
    # FAILS CLOSED (rc 2 + diagnostics on stderr) — never silently falls
    # back to another checkout, which could mutate or rebuild the wrong
    # flake. Without an explicit value the conventional candidates are
    # probed (rc 1 when none has flake.nix). The returned directory is
    # canonical (symlinks/`.`/trailing slashes resolved via pwd -P) so
    # every consumer sees the same JSON location.
    omarchy_flake_diag() {
      {
        echo "omarchy-nix: invalid OMARCHY_NIX_FLAKE: '$1'"
        echo "  expected: a directory containing flake.nix, or the path to a flake.nix file"
        echo "  required file: <dir>/flake.nix"
        echo "  refusing to fall back to another checkout — fix or unset the variable"
      } >&2
    }

    # A fallback candidate is skipped only when it is PROVABLY a foreign
    # flake: its nixosConfigurations evaluate fine but have no entry for
    # this host (the rebuild target used downstream) — i.e. a library
    # checkout like a bare ~/Projects/omarchy-nix clone of omarchy-nix
    # itself, which ships demo/example host configs but not the consumer's.
    # Any eval failure (stub/broken flake, offline input
    # fetch, no nixosConfigurations output at all) means "unknown" and the
    # candidate STAYS: a consumer flake whose eval is temporarily broken
    # must never be skipped past.
    flake_is_foreign_library() {
      local verdict rc=0
      verdict=$(nix --extra-experimental-features 'nix-command flakes' \
        eval --raw "$1#nixosConfigurations" \
        --apply 'attrs: if attrs ? "'"$2"'" then "host" else "foreign"' 2>/dev/null) || rc=$?
      ((rc == 0)) || return 1
      [[ $verdict == foreign ]]
    }

    resolve_flake_dir() {
      local v=''${OMARCHY_NIX_FLAKE:-} d canon
      if [[ -n $v ]]; then
        if [[ -d $v && -f $v/flake.nix ]]; then
          d=$v
        elif [[ -f $v && ''${v##*/} == flake.nix ]]; then
          d=$(dirname -- "$v")
        else
          omarchy_flake_diag "$v"
          return 2
        fi
        canon=$(cd -- "$d" 2>/dev/null && pwd -P) || {
          omarchy_flake_diag "$v"
          return 2
        }
        printf '%s\n' "$canon"
        return 0
      fi
      local c host
      # uname -n (coreutils) == kernel nodename == hostname; works even in
      # minimal environments without the hostname binary.
      host=$(uname -n)
      for c in "$HOME/omarchy-nix" "$HOME/Projects/omarchy-nix" /etc/nixos; do
        if [[ -f $c/flake.nix ]] && ! flake_is_foreign_library "$c" "$host"; then
          canon=$(cd -- "$c" 2>/dev/null && pwd -P) || continue
          printf '%s\n' "$canon"
          return 0
        fi
      done
      return 1
    }

    # NixOS puts the setuid sudo wrapper at /run/wrappers/bin/sudo (same as B4).
    if [[ -x /run/wrappers/bin/sudo ]]; then
      sudo() { command /run/wrappers/bin/sudo "$@"; }
    fi

    # resolve_flake_dir_or_die — resolver + the standard error mapping for
    # mutating commands (rc 2 = invalid explicit, rc 1 = no candidates).
    # Prints the resolved dir on stdout; dies (red message) otherwise. When
    # called in a command substitution the die kills the subshell and the
    # caller's set -e finishes the exit, so `d=$(resolve_flake_dir_or_die)`
    # is safe in the sourced scripts.
    resolve_flake_dir_or_die() {
      local rc=0 d
      d=$(resolve_flake_dir) || rc=$?
      if ((rc == 2)); then
        die "Invalid OMARCHY_NIX_FLAKE (see above) — fix or unset it. Nothing was changed."
      elif ((rc != 0)); then
        die "No consumer flake with nixosConfigurations.\"$(uname -n)\" found under ~/omarchy-nix, ~/Projects/omarchy-nix or /etc/nixos. Set OMARCHY_NIX_FLAKE to your config flake directory (or its flake.nix file). Nothing was changed."
      fi
      printf '%s\n' "$d"
    }

    # txn_begin <command-name> <ids...> — resolve flake, open the per-operation
    # audit log, and take the flock for this JSON. The lock lives in the state
    # dir (always user-writable, so it also covers root-owned flakes) and is
    # keyed by the JSON path; it is held until process exit, which serializes
    # ALL add/remove operations — including their rebuilds.
    txn_begin() {
      local cmd="$1"; shift
      flake_dir=$(resolve_flake_dir_or_die)
      json="$flake_dir/omarchy-packages.json"
      mkdir -p "$STATE_DIR/locks"
      op_log="$STATE_DIR/$(date +%Y%m%d-%H%M%S)-$$.log"
      local key
      key=$(printf '%s' "$json" | sha256sum | cut -d' ' -f1)
      exec 9>"$STATE_DIR/locks/$key.lock"
      flock -w 600 9 || die "Another install/remove operation has held the lock for 10 minutes. Check for a stuck omarchy-nix-add/remove process (do NOT remove the lock file — a live holder would keep the old lock while new operations take a fresh one). Nothing was changed."
      {
        echo "command: $cmd"
        echo "ids: $*"
        echo "flake: $flake_dir"
        echo "pid: $$"
        echo "started: $(date -Is)"
      } >>"$op_log"
    }

    txn_hash() {
      if [[ ! -f $json ]]; then
        echo absent
      elif [[ -r $json ]]; then
        sha256sum "$json" | cut -d' ' -f1
      else
        sudo sha256sum "$json" | cut -d' ' -f1
      fi
    }

    # Read + validate the JSON under the lock. Sets TXN_PREIMAGE (content),
    # TXN_PREIMAGE_EXISTS, TXN_PRE_HASH.
    txn_read() {
      if [[ -f $json ]]; then
        TXN_PREIMAGE_EXISTS=1
        if [[ -r $json ]]; then TXN_PREIMAGE=$(cat "$json"); else TXN_PREIMAGE=$(sudo cat "$json"); fi
      else
        TXN_PREIMAGE_EXISTS=0
        TXN_PREIMAGE='{"packages":[],"features":[]}'
      fi
      jq -e 'type == "object"
        and (((.packages // []) | type == "array") and (all(.packages[]?; type == "string")))
        and (((.features // []) | type == "array") and (all(.features[]?; type == "string")))' \
        <<<"$TXN_PREIMAGE" >/dev/null ||
        die "omarchy-packages.json has an unexpected shape — fix or remove $json. Nothing was changed. (log: $op_log)"
      TXN_PRE_HASH=$(txn_hash)
    }

    # txn_write <content> — unique temp + atomic rename inside the same dir
    # (sudo variants when the flake dir is root-owned).
    txn_write() {
      local tmp="$json.tmp.$$"
      if [[ -w $flake_dir ]]; then
        printf '%s\n' "$1" >"$tmp" && mv "$tmp" "$json"
      else
        printf '%s\n' "$1" | sudo tee "$tmp" >/dev/null && sudo mv "$tmp" "$json"
      fi
    }

    # Git-based consumer flakes only snapshot tracked files — register the
    # JSON with intent-to-add so `nixos-rebuild --flake` can see it.
    txn_git_register() {
      [[ -e $flake_dir/.git ]] || return 0
      git -C "$flake_dir" add -N omarchy-packages.json >/dev/null 2>&1 ||
        sudo git -C "$flake_dir" add -N omarchy-packages.json >/dev/null 2>&1 || true
    }

    # txn_apply <new-content> — write, register, log the post hash.
    txn_apply() {
      txn_write "$1"
      txn_git_register
      echo "pre-hash: $TXN_PRE_HASH" >>"$op_log"
      echo "post-hash: $(txn_hash)" >>"$op_log"
      TXN_POST_HASH=$(txn_hash)
    }

    # txn_rollback — restore the preimage, but ONLY if the JSON still holds
    # exactly what this operation wrote (the held lock serializes cooperating
    # operations; the hash check protects against non-cooperating writers such
    # as a hand edit during the rebuild — we never revert someone else's
    # newer mutation).
    txn_rollback() {
      local now
      now=$(txn_hash)
      if [[ $now != "$TXN_POST_HASH" ]]; then
        echo "rollback: SKIPPED (json changed by someone else: $now != $TXN_POST_HASH)" >>"$op_log"
        warn "omarchy-packages.json changed since our write — leaving it untouched (preimage is in $op_log)."
        return 1
      fi
      if ((TXN_PREIMAGE_EXISTS)); then
        txn_write "$TXN_PREIMAGE"
      else
        rm -f "$json" 2>/dev/null || sudo rm -f "$json"
      fi
      echo "rollback: restored preimage" >>"$op_log"
      warn "Rebuild failed — your previous package list was restored."
    }

    # txn_rebuild — one rebuild per operation; failure rolls back (above).
    # OMARCHY_NIX_UPDATE_DRY_RUN=1 exercises the whole transaction minus the
    # rebuild (unchanged interface).
    txn_rebuild() {
      if [[ ''${OMARCHY_NIX_UPDATE_DRY_RUN:-} == 1 ]]; then
        echo "DRY-RUN: sudo nixos-rebuild ''${OMARCHY_NIX_REBUILD_CMD:-switch} --flake $flake_dir" | tee -a "$op_log"
        echo "result: dry-run" >>"$op_log"
        return 0
      fi
      log "Rebuilding the system (this can take a minute or two)...  (full log: $op_log)"
      if sudo nixos-rebuild "''${OMARCHY_NIX_REBUILD_CMD:-switch}" --flake "$flake_dir" 2>&1 | tee -a "$op_log"; then
        echo "result: rebuild ok" >>"$op_log"
        return 0
      fi
      echo "result: rebuild failed" >>"$op_log"
      txn_rollback || true
      die "Something went wrong during the rebuild — see the full log: $op_log"
    }
    EOF
    chmod 644 "$dest/bin/omarchy-nix-pkglib"

    # omarchy-nix-add / omarchy-nix-remove: menu-driven package management.
    # Writes omarchy-packages.json next to the consumer flake (shared
    # candidate resolution), then runs ONE nixos-rebuild per invocation so the
    # change applies immediately and visibly (upstream parity). Accepts
    # multiple ids per call (one transaction, one rebuild).
    cat >"$dest/bin/omarchy-nix-add" <<'EOF'
    #!/bin/bash
    # omarchy-nix: add catalog entries (or raw nixpkgs attributes) to
    # omarchy-packages.json and rebuild the system.

    set -euo pipefail
    source "$(dirname "''${BASH_SOURCE[0]}")/omarchy-nix-pkglib"

    (($# > 0)) || die "Usage: omarchy-nix-add <menu-entry-id|nixpkgs-attribute> [more ids...]"

    # --- resolve every id first (read-only): catalog entries contribute their
    # pkgs/feature/configSeed; raw attributes get a best-effort nixpkgs check.
    pkgs=()
    features=()
    seeds=()
    for id in "$@"; do
      if jq -e --arg id "$id" '.entries[$id]' "$CATALOG" >/dev/null 2>&1; then
        mapfile -t _p < <(jq -r --arg id "$id" '.entries[$id].pkgs // [] | .[]' "$CATALOG")
        pkgs+=("''${_p[@]}")
        _f=$(jq -r --arg id "$id" '.entries[$id].feature // ""' "$CATALOG")
        [[ -z $_f ]] || features+=("$_f")
        _s=$(jq -r --arg id "$id" '.entries[$id].configSeed // ""' "$CATALOG")
        [[ -z $_s ]] || seeds+=("$_s")
      else
        if ! nix eval --quiet "nixpkgs#$id.name" &>/dev/null; then
          die "Sorry — '$id' was not found in nixpkgs (or nixpkgs is unreachable). Nothing was changed."
        fi
        pkgs+=("$id")
      fi
    done

    # --- one locked transaction for the whole batch --------------------------
    txn_begin omarchy-nix-add "$@"
    txn_read

    pkgs_json=$(printf '%s\n' "''${pkgs[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc 'unique')
    features_json=$(printf '%s\n' "''${features[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc 'unique')
    new=$(jq --argjson p "$pkgs_json" --argjson f "$features_json" '
      .packages = (((.packages // []) + $p) | unique)
      | .features = (((.features // []) + $f) | unique)
    ' <<<"$TXN_PREIMAGE")

    if [[ $(jq -cS . <<<"$new") == $(jq -cS . <<<"$TXN_PREIMAGE") ]]; then
      echo "result: no-op (already installed)" >>"$op_log"
      log "Already installed — everything requested is already in $(basename "$json"). Nothing to do."
      # Retry git registration in case a previous run's git add -N failed
      # (git-based flakes only snapshot tracked files).
      txn_git_register
      exit 0
    fi

    txn_apply "$new"
    txn_rebuild

    # Upstream parity: seed default configs (e.g. alacritty) on first install.
    for _s in "''${seeds[@]:-}"; do
      [[ -n $_s && ! -e $HOME/.config/$_s ]] || continue
      cp -r --no-preserve=mode "$OMARCHY_PATH/default/$_s" "$HOME/.config/$_s" 2>/dev/null || true
    done

    # Refresh the package-search index in the background for omarchy-nix-search.
    # 9>&- closes the inherited lock fd — otherwise the (minutes-long) index
    # build would keep the transaction lock held after this script exits.
    (omarchy-nix-search --refresh >/dev/null 2>&1 9>&- &)

    log "Done — $* installed."
    EOF
    chmod +x "$dest/bin/omarchy-nix-add"

    cat >"$dest/bin/omarchy-nix-remove" <<'EOF'
    #!/bin/bash
    # omarchy-nix: remove catalog entries (or raw nixpkgs attributes) from
    # omarchy-packages.json and rebuild the system.

    set -euo pipefail
    source "$(dirname "''${BASH_SOURCE[0]}")/omarchy-nix-pkglib"

    # Interactive multi-select when no ids are given (tab toggles, enter runs
    # ONE transaction + ONE rebuild for all picks).
    if (($# == 0)); then
      _jdir=$(resolve_flake_dir_or_die)
      [[ -f $_jdir/omarchy-packages.json ]] || die "Nothing to remove — omarchy-packages.json does not exist yet."
      mapfile -t _picked < <(jq -r '(.packages // [])[], (.features // [])[]' "$_jdir/omarchy-packages.json" |
        fzf --multi --prompt="Remove package> " --header="tab: multi-select, enter: remove all picks")
      ((''${#_picked[@]} > 0)) || exit 0
      set -- "''${_picked[@]}"
    fi

    # --- resolve every id: catalog entries expand to their pkgs/feature;
    # everything else is classified AFTER the locked read by membership in
    # the JSON itself, so a feature that is no longer (or not yet) in the
    # catalog (renamed upstream, hand edit) stays removable.
    pkgs=()
    features=()
    raw=()
    for id in "$@"; do
      if jq -e --arg id "$id" '.entries[$id]' "$CATALOG" >/dev/null 2>&1; then
        mapfile -t _p < <(jq -r --arg id "$id" '.entries[$id].pkgs // [] | .[]' "$CATALOG")
        pkgs+=("''${_p[@]}")
        _f=$(jq -r --arg id "$id" '.entries[$id].feature // ""' "$CATALOG")
        [[ -z $_f ]] || features+=("$_f")
      else
        raw+=("$id")
      fi
    done

    # --- one locked transaction for the whole batch --------------------------
    txn_begin omarchy-nix-remove "$@"
    [[ -f $json ]] || die "Nothing to remove — omarchy-packages.json does not exist yet."
    txn_read

    for id in "''${raw[@]:-}"; do
      [[ -n $id ]] || continue
      if jq -e --arg id "$id" '.features // [] | index($id)' <<<"$TXN_PREIMAGE" >/dev/null; then
        features+=("$id")
      else
        pkgs+=("$id")
      fi
    done

    pkgs_json=$(printf '%s\n' "''${pkgs[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc 'unique')
    features_json=$(printf '%s\n' "''${features[@]:-}" | { grep -v '^$' || true; } | jq -R . | jq -sc 'unique')
    new=$(jq --argjson p "$pkgs_json" --argjson f "$features_json" '
      .packages = ((.packages // []) - $p)
      | .features = ((.features // []) - $f)
    ' <<<"$TXN_PREIMAGE")

    if [[ $(jq -cS . <<<"$new") == $(jq -cS . <<<"$TXN_PREIMAGE") ]]; then
      echo "result: no-op (not installed)" >>"$op_log"
      log "Not installed — nothing requested is in $(basename "$json"). Nothing to do."
      exit 0
    fi

    txn_apply "$new"
    txn_rebuild

    log "Done — $* removed."
    EOF
    chmod +x "$dest/bin/omarchy-nix-remove"

    # omarchy-nix-search: fzf over a cached nixpkgs index -> omarchy-nix-add.
    # The index builds on first use (slow, one-off) and refreshes in the
    # background after every successful omarchy-nix-add rebuild.
    cat >"$dest/bin/omarchy-nix-search" <<'EOF'
    #!/bin/bash
    # omarchy-nix: search nixpkgs (fzf) and install the picks via ONE
    # omarchy-nix-add transaction (tab multi-selects).

    set -euo pipefail

    INDEX_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/omarchy"
    INDEX="''${OMARCHY_NIX_INDEX_FILE:-$INDEX_DIR/nixpkgs-index-v2.tsv}"

    # Index columns: name, description, version. Underscore-prefixed attrs
    # (nixpkgs naming for attrs that can't start with a digit, e.g. _2bwm)
    # sort LAST — upstream's pacman -Slq has no such artifacts.
    # Filename carries a version tag (v2) so a stale 2-column index from an
    # older script build is never picked up by the freshness check.
    build_index() {
      mkdir -p "$INDEX_DIR"
      echo "Building the package index (first run only — this takes a minute)..." >&2
      nix search nixpkgs "" --json 2>/dev/null |
        jq -r 'to_entries[] | [(.key | sub("^legacyPackages\\.[^.]+\\."; "")), (.value.description // ""), (.value.version // "")] | @tsv' |
        awk -F'\t' '{ print (($1 ~ /^_/) ? 1 : 0) "\t" $0 }' |
        LC_ALL=C sort -u |
        cut -f2- >"$INDEX.tmp"
      mv "$INDEX.tmp" "$INDEX"
    }

    # Upstream parity (omarchy-pkg-install): names in the list, details in a
    # preview pane. Preview data comes from the index itself (instant) — a
    # per-row nix eval would be far too slow.
    fzf_args=(
      --multi
      --prompt="Install package> "
      --header="tab: multi-select, enter: install all picks"
      --delimiter='\t'
      --with-nth=1
      --preview 'printf "Name: %s\nVersion: %s\n\n%s\n" {1} {3} {2}'
      --preview-label='alt-p: toggle description, alt-j/k: scroll'
      --preview-label-pos='bottom'
      --preview-window 'down:65%:wrap'
      --bind 'alt-p:toggle-preview'
      --bind 'alt-d:preview-half-page-down,alt-u:preview-half-page-up'
      --bind 'alt-k:preview-up,alt-j:preview-down'
      --color 'pointer:green,marker:green'
    )

    case "''${1:-}" in
      --refresh)
        build_index
        exit 0
        ;;
      --filter)
        [[ -f $INDEX ]] || exit 1
        fzf --filter="''${2:-}" <"$INDEX" | cut -f1
        exit 0
        ;;
    esac

    [[ -f $INDEX ]] || build_index
    mapfile -t choices < <(fzf "''${fzf_args[@]}" <"$INDEX" | cut -f1 || true)
    ((''${#choices[@]} > 0)) || exit 0
    exec omarchy-nix-add "''${choices[@]}"
    EOF
    chmod +x "$dest/bin/omarchy-nix-search"

    runHook postInstall
  '';

  # pythonWithGi's store path is substituted into omarchy-file-select's
  # /usr/bin/python3 shebang below; the wrap in postFixup then
  # gives its runtime `gi.repository.Gio/GLib` import the typelibs, without
  # touching session env.
  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/share/omarchy/bin/omarchy-file-select \
      --prefix GI_TYPELIB_PATH : ${glib}/lib/girepository-1.0
  '';

  meta = {
    description = "Vendored basecamp/omarchy (Quattro) tree for NixOS";
    homepage = "https://github.com/basecamp/omarchy";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    # The output is data-only (no bin/ at the top level — the scripts live
    # under share/omarchy/bin and are dispatched via $OMARCHY_PATH). NixOS
    # buildEnv links a package's outputs into /run/current-system/sw based on
    # this attribute; without it the share/ tree is silently dropped and
    # $OMARCHY_PATH would point at a store path that is never on the system
    # profile. Explicitly request the single `out` output.
    outputsToInstall = [ "out" ];
  };
})
