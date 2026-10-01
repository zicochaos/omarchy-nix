# Changelog

All notable changes to omarchy-nix, newest first. Dates are UTC.
Upstream adaptation details and the bump checklist:
[`docs/UPSTREAM.md`](docs/UPSTREAM.md).

## 2026-10-01

- **CI checks the whole flake on every PR, and the nightly became an
  input canary.** The fast lane now runs `nix flake check --no-build`, so
  a consumer-side evaluation break (the `example` configuration) or a
  broken host configuration fails the PR instead of the nightly after
  merge. The nightly used to re-check an unchanged, fully cached tree and
  pass without running anything. It now updates every flake input in its
  own checkout (nothing is committed), builds the package, runs the full
  flake check, including the VM tests, which the new lock forces to
  re-run, and the all-systems evaluation, so upstream breakage shows up
  before the next bump. Failure logs are uploaded again: the old upload
  action refused Forgejo outright, and every step now records its output
  as it runs. Runs on `main` are no longer cancelled by the next merge;
  they queue. The VM lane runs its tests two at a time to stay inside the
  runner's 16 GiB, and finds them by itself instead of from a hand-kept
  list. The Install-menu packages the flake builds itself (claude-desktop,
  omp, zcode-desktop, hermes-agent) are now built by a check
  (`omarchy-owned-packages`) instead of only evaluated.
- **Several tests could not fail, and now can.** The SDDM greeter check
  passed a theme whose QML failed to load: SDDM falls back to its
  built-in theme and keeps running, and its errors go to the journal,
  not the output the test read. It now reads the journal and fails on the
  fallback or any QML error. Also fixed: the agent-skill check's
  "forbidden Arch guidance" lines never fired; the quickshell version
  check accepted 0.3.10; the Super+Enter test could not notice a second
  window; and several checks passed on empty input. The four VM tests are
  type-checked again and wait for real conditions instead of fixed
  sleeps.
- **Catalog permits must be needed.** `checks.catalog-consistency` now
  withdraws each unfree and insecure permit of every Install-menu entry
  in turn and requires the entry to stop evaluating, so a permit that
  does nothing (like bitwarden's former electron-39 one) fails the check.
- **The shell's exec sites are pinned by a reviewed list.**
  `checks.omarchy-ux` compares every program the vendored QML shell
  launches with `tests/fixtures/qml-exec-sites.txt`, so an upstream bump
  that adds or changes one fails with a diff instead of a changed count.
  Regenerating the list is part of the bump checklist. The manual
  quickshell reload probe is now evaluated by `nix flake check`; it had
  broken twice unnoticed.
- **`omarchy update` offers the reboot again.** Updates rebuild with
  `nixos-rebuild boot`, which never changes the running system, so the
  end-of-update reboot prompt (it compared the booted and the running
  kernel) never fired. It now appears whenever a new generation is
  installed but not active, and says the update takes effect only after
  the reboot; the new generation's migrations run at the first login
  after it.
- **Menu installs and `omarchy update` no longer interleave.** The
  update's flake update and rebuild take the same per-flake lock as
  Install/Remove, and a waiting operation says so.
- **A package that installed with failing units stays installed.** When
  `nixos-rebuild switch` installs the new generation and then reports
  failed units, `omarchy-packages.json` keeps the package instead of
  rolling back and silently dropping it on the next rebuild.
- **NixOS option picks from Install → Package work.** The picker passed
  its own prompt text along with the value, so every option pick was
  refused. Values must now be exactly one JSON value; an empty value or
  `1 2` is refused before anything is locked or written.
- **Migrations that ask a question no longer swallow the queue.** A
  migration reading stdin consumed the list of later migrations, which
  were then skipped silently; the list now travels on its own file
  descriptor, as upstream does.
- **The Neovim remote-clipboard migrations find their source.** Both
  always skipped on NixOS. They now install and repair the provider, keep
  a dotfile-managed (symlinked) config untouched, and stop resetting
  `options.lua` to mode 0600. The tmux and browser-flags migrations now
  edit symlinked configs through the link and skip read-only ones instead
  of failing every update.
- **The Arch-mutator scan is fail-closed for real.** Any `sudo`/`pkexec`
  call now needs a classification, files are scanned whatever their mode,
  and the scan covers `install/user/**`, `default/bash/fns` and the
  NixOS adapters; manifest keys are checked against the upstream tree.
  `omarchy-install-gaming-lutris` and `omarchy-remove-service-1password`
  became declarative notes (their `sudo` steps target `/usr` paths NixOS
  does not have). Every hand-written overwrite of an upstream file now
  fails the build if that file disappears upstream.
- **Smaller hardening:** the Install/Remove and search scripts use
  unpredictable temp files and keep the JSON's mode; root git runs only
  in root-owned flakes, with fsmonitor and hooks disabled; the update's
  `OMARCHY_PATH` check requires a store root; the host name is no longer
  spliced into the resolver's Nix expression; stub notes are
  shell-quoted; and before the first install the menu resolves the flake
  once per menu batch instead of 58 times. New checks:
  `omarchy-update-flow`, `omarchy-migration-adapters`,
  `omarchy-build-guards`, `omarchy-bash-syntax`.
- **Hyprland is pinned to the v0.56.2 release, and 32-bit Mesa now
  matches.** The `hyprland` input followed Hyprland's main branch (an
  untagged 2026-07-29 snapshot reporting 0.56.0). It now pins the v0.56.2
  release commit `34170f6`. The `v0.56.2` tag itself (`efb5099`) only
  adds an automated lock bump to a nixpkgs with glaze 8, which the
  release's CMake rejects, so the tag's flake does not build.
  `hardware.graphics.package` and `package32` both come from Hyprland's
  own nixpkgs (Mesa 26.1.5); before, 32-bit clients such as Steam loaded
  stable's 26.1.8 next to a 26.1.5 64-bit driver. Neither this Hyprland
  build nor the previous pin is on hyprland.cachix.org (it only keeps
  recent main builds), so Hyprland compiles locally on a fresh install.
- **The bar's keyboard-layout widget works again.** Since upstream
  2026-08-09 the widget and `omarchy-menu-keybindings` call `xkbcli`,
  which was not on PATH. The module now ships `libxkbcommon`. The new
  `checks.omarchy-qml-commands` requires every program the vendored shell
  starts by literal name to resolve on the system PATH.
- **`omarchy.exclude_packages` accepts the attribute names the docs ask
  for.** `"libreoffice-fresh"`, `"tesseract5"` and `"qt6.qtwayland"` now
  remove exactly that package; before they matched nothing, because
  matching only compared package names. Package names still work. An
  entry that matches nothing now produces an evaluation warning instead
  of silently doing nothing. Excluding `"chromium"` also drops its
  desktop alias.
- **A consumer's own `allowUnfreePredicate` no longer breaks
  evaluation.** The module's unfree whitelist (obsidian plus
  menu-installed unfree packages) was a `mkDefault` predicate that any
  consumer predicate replaced. It now uses the merging
  `nixpkgs.config.allowUnfreePackages` list.
- **udiskie runs once.** Upstream's autostart already launches it, and
  the module's extra user service doubled mounts and notifications.
- **New `omarchy.systemTuning.enable` (default on), and the zram tuning
  now follows zram.** One switch drops the module's sysctls, USB
  autosuspend-off, the Kyber scheduler rule and the zswap switch; before,
  the modprobe and udev lines needed `mkForce`. With
  `zramSwap.enable = false`, the zram reclaim sysctls (swappiness 150,
  page-cluster 0, …) and zswap-off no longer apply.
- **New `omarchy.hyprlandCache.enable` (default on)** removes the
  Hyprland Cachix substituter and its key on hosts that must not trust a
  third-party cache.
- **SDDM greeter, autologin relogin and PipeWire defaults are
  overridable.** The greeter command no longer uses `mkForce`.
  `relogin`, rtkit and the PipeWire switches are `mkDefault`, so a
  consumer's `false` replaces them instead of conflicting.
- **The greeter preselects the uwsm session without autologin.** The
  theme's own "prefer uwsm" logic never fires under SDDM 0.21 (it asks
  for a display role the session model does not answer), and
  `DefaultSession` was empty. A desktop module's own default (for
  example Plasma's) still wins. The SDDM theme is only installed while
  SDDM is the display manager.
- **`omarchy-migrate` can no longer stall the graphical session.** It now
  has a 2-minute start timeout; a migration that times out is retried at
  the next login.
- **`omarchy.monitors` accepts Hyprland's full monitor grammar.** That
  covers `auto-center-*` positions, `maxwidth` and `"NAME, disable"`, and
  the validator now rejects unknown `auto-*` positions and scales below
  0.25. `omarchy.theme` rejects `.` and `..`.
- Checks: `omarchy-disabled-state` now compares the whole system, and
  `omarchy-option-validation` checks each rejected value against a valid
  one of the same option. Seven new checks cover exclusions, unfree
  handling, udiskie, tuning, overrides and the module defaults (sshd,
  nixPath, Plymouth, theme, cache).
- **Home Manager no longer overwrites files your own Home Manager
  configuration manages.** The seed treated every symlink into the Nix
  store as a leftover from old module versions, including the links Home
  Manager had just created: with `programs.git` or `programs.starship`
  (likewise tmux, kitty, foot, alacritty, btop, lazygit, ghostty, imv,
  fastfetch, opencode) the first switch replaced the generated file with
  upstream's copy, and the next one aborted with "Existing file ... would
  be clobbered". A config directory Home Manager owns as a whole broke
  the first switch. Files Home Manager manages (a `home.file` or
  `xdg.configFile` target, or a file inside one) are now never seeded,
  and only links into an omarchy tree are replaced; other tools' links
  stay.
- **`omarchy.*` set inside Home Manager: one source, and a warning when
  it is ignored.** Under NixOS the Home-Manager module takes `package`,
  `nvimPackage`, `theme`, `scale` and `monitors` from the system
  configuration; a different per-user value used to be dropped silently
  and now gets an evaluation warning, as does any option only the NixOS
  module reads. Standalone Home Manager reads its own values, and the
  flake now provides the omarchy package there (before,
  `omarchy.enable = true` seeded nothing); enabling without any package
  fails with an assertion. The module is exported as
  `homeModules.default`, the output name Nix knows;
  `homeManagerModules.default` keeps working.
- **The default-browser step runs.** Home Manager activates with its own
  minimal PATH, which has no `xdg-settings`, so the step that initializes
  `chromium.desktop` never ran there; it now calls xdg-settings by store
  path, and stays out when Home Manager manages `mimeapps.list`
  (`xdg.mimeApps`).
- **The Neovim starter seed is retried after a failure.** A failed
  `omarchy-nvim-setup` left a half-written `~/.config/nvim` that was
  never retried, silently (it always failed after the copy, because
  `xdg-mime` is not on the activation PATH). The seed now runs in a
  staging directory with xdg-utils available and is moved into place
  only when it succeeded; a failure prints a warning and the next
  activation tries again.
- **Dry runs (`home-manager switch -n`) no longer change `$HOME`.** The
  seeds, the `~/.bashrc` seed, the first-run markers, the theme render
  and the move-aside of user-owned skill directories all wrote during a
  dry run; the move-aside also runs after Home Manager's own checks now.
  New checks: `omarchy-hm-activation` runs real Home Manager activations
  in the build sandbox (owned files, `monitors.lua`, `~/.bashrc`, user
  edits, legacy links, skill move-aside, nvim retry, dry run),
  `omarchy-hm-eval` covers where the values come from, and
  `omarchy-browser-default` runs the real activation instead of the step
  text with a PATH stub.
- **herdr evaluates without import-from-derivation.** `pkgs/herdr.nix`
  read `Cargo.lock` and libghostty-vt's zon2nix file out of the fetched
  source, so with `allow-import-from-derivation = false` neither `.#herdr`
  nor any host config evaluated (herdr is a default app, so every
  consumer was affected). The crates now come from `cargoHash`, and the
  zon file is committed as `pkgs/herdr-zig-deps.nix`, with the
  regeneration steps in herdr.nix's header. herdr 0.9.1 → 0.9.3.
- Package bumps: aether 4.28.0 → 4.31.1, ttfx 0.3.2 → 0.5.0, monologue
  0.2.0 → 0.3.0, omp 18.2.6 → 18.4.5, owe 0.2.7 → 0.2.8, claude-desktop
  2.2553.1 → 2.9939.4, zcode-desktop 3.14.0 → 3.14.4. `hermes-agent`
  `d595e63` (2026-09-12) → `6633626` (2026-10-01); upstream moved to date
  releases, so the package is now named `hermes-agent-0.0.0`
  (`hermes --version` reports 2026.9.24). Its home-manager input now
  follows ours instead of locking a second one.
- **`try` no longer adds `bin/lib/` to every profile.** Its Ruby sources
  live in `share/try` and `bin/try` is a wrapper.
- The Bitwarden Install entry no longer permits the insecure
  `electron-39.8.10`; bitwarden-desktop on the pin evaluates without it.
  omacalc's license is MIT + OFL-1.1 (embedded fonts), and the sources
  follow upstream's GitHub moves (`bjarneo/aether` and `omacom-io/*` →
  `omacom/*`), with unchanged hashes.
- **Security: two passwordless paths to root removed.** The NixOS module
  granted every wheel user NOPASSWD `sudo tzupdate` with any arguments;
  tzupdate's `-l`/`-d`/`-z` flags write symlinks and files at
  caller-chosen paths, so any process running as that user could write
  root-owned files (for example a script that root's shells source) without
  the password. Nothing ran `sudo tzupdate`, and upstream only grants
  `timedatectl set-timezone <zone>`, which stays. The module also put
  `@wheel` in `nix.settings.trusted-users`, which Nix treats as
  root-equivalent; the Hyprland Cachix it was added for works from the
  system-level substituter and key settings alone. Both grants are gone,
  and `checks.omarchy-etc-parity` now fails if either comes back. A
  consumer who wants a trusted Nix user sets `nix.settings.trusted-users`
  in their own configuration.

## 2026-09-30

- **Bash gets the Omarchy shell setup.** Before this, nothing on the port
  sourced upstream's `default/bash/rc`, so bash users had none of the
  Omarchy aliases, functions, starship/zoxide init or fzf key bindings.
  The Home-Manager module now seeds `~/.bashrc` from upstream's
  `default/bashrc` (the Arch `/etc/skel` file) when the file is absent,
  and never replaces an existing file or link. `default/bash/init` reads
  fzf's key bindings from `/run/current-system/sw/share/fzf` (the module
  links `/share/fzf` into the system profile); upstream's
  `/usr/share/fzf` path does not exist on NixOS. The ux VM test asserts
  the seed and that an interactive bash has the `ff` alias and the
  Ctrl-T/Ctrl-R fzf widgets.
- `nixpkgs` (nixos-26.05) `21a67dc` (2026-09-11) → `7fc6f2c`
  (2026-09-28) and home-manager (release-26.05) `b1d1b60` (2026-09-12)
  → `e5fcd29` (2026-09-30). Stable nixpkgs still carries quickshell
  0.3.0, so the 0.3.1 pin stays.
- Upstream bump `349ecc0` → `8b4eae6` (2026-09-29, 29 commits). What
  changed in the port:
  - **Hype** 0.4.3, upstream's new default Markdown presentation app, is
    packaged as `pkgs/hype.nix` (not in nixpkgs) and ships in
    `omarchy.appPackages`. Its code-block highlighter `source-highlight`
    is on the wrapper PATH; ffmpeg comes from the session PATH as for
    omacut and monologue. Migration `1790542069` (install via
    `omarchy-pkg-add`) is `skip`.
  - **SSH Agent**: upstream's new Setup/Remove entries toggle
    `gcr-ssh-agent.socket` per user. NixOS already runs it system-wide
    (`services.gnome.gcr-ssh-agent`, which defaults to the
    `gnome-keyring` the module enables), and a user `systemctl --user
    disable` cannot undo a unit enabled from `/etc`. Both scripts are
    declarative-note stubs and both menu entries are hidden.
  - **No-animations mode** (`omarchy-toggle-animations`, on by default
    in VMs through first-run's `vm-no-animations.sh`) is kept. The
    first-run copy and `omarchy-hyprland-toggle` now copy flag files
    with `--no-preserve=mode`. A 0444 flag copied from the store made a
    second `on` fail, because `cp` cannot open the read-only
    destination.
  - Migration `1788279117` (retire the YT6801 DKMS driver with pacman +
    modprobe) is `skip`: kernel modules are `boot.kernelPackages` here.
  - Kept verbatim: the browser handoff to a running Chromium (it only
    recognizes Arch's `/usr/bin` browsers, so NixOS launches fall back
    to the existing `uwsm-app` path), the `mimeapps.list` default-browser
    lookup, grouped notifications, the faster bash prompt, and Hunk
    theme sync.
  - ux VM test: the QML exec baseline goes 134 → 135 for
    `Commons/Style.qml`'s new `hyprctl getoption animations:enabled`
    probe.
  - README: the upstream-owned package count in the intro read 13; it
    is now 16, matching the list.

## 2026-09-27

- Upstream bump `60663fa` → `349ecc0` (2026-09-27, 165 commits). What
  changed in the port:
  - **Update flow**: upstream rewrote `omarchy-update` around
    command-scoped sudo (one password prompt per update, `bash -p`
    startup verified through `/proc/$$/exe`, every tool called by an
    absolute `/usr/bin` path, AUR phase through a `sudo -N` wrapper).
    The hardening is kept. On NixOS the tools point at store paths and
    the setuid `/run/wrappers/bin/{sudo,pkexec}`, the sanitized PATH is
    `/run/wrappers/bin:/run/current-system/sw/bin`, and the source-root
    check compares resolved paths, because `$OMARCHY_PATH` is a
    symlinked profile path. An unmapped `/usr/bin` tool now fails the
    build. The port's `omarchy-update-restart` gained upstream's
    `--services-only`/`--reboot-only` phases. `omarchy-remove-dev-env`'s
    sudo probes use the wrapper too.
  - **Elsewhen** moved into the shell as the first-party
    `omarchy.elsewhen`, so `pkgs/elsewhen.nix`, the plugin fold-in, the
    home-manager plugin link and the `1789581661` adapter are gone.
    Home Manager removes the old link on the next switch and upstream
    migration `1790528634` renames the bar entry.
  - **New upstream-owned packages** (none are in nixpkgs):
    - `omasnap` 1.21.0: screenshots. The PRINT binding and
      `omarchy-clipboard-open` exec it, and it replaces tensaku, which
      upstream dropped. `pkgs/tensaku.nix` is removed.
    - `owe` 0.2.7: video backgrounds and the lock-screen feed. The
      shell's own video playback and `qt6.qtmultimedia` are gone
      upstream. `owed.service` is registered through `systemd.packages`
      and enabled for `graphical-session.target`. First-run and
      migration `1789764927` install its theme-set hook from
      `/run/current-system/sw/share/owe` and skip cleanly when `owe` is
      excluded.
    - `monologue` 0.2.0: the new default webcam recorder.
  - `omarchy-nvim` 2026.8.13 → **2026.9.21**. It carries the
    remote-clipboard fix that migration `1788996284` (a NixOS adapter:
    stale-provider hash gate instead of `pacman -Q`/`vercmp`) installs.
  - The first-login theme render (home-manager activation) now gets
    `gawk` and `util-linux` on its PATH. Upstream's template renderer
    became a single awk pass and `omarchy-theme-set` takes a `flock`, so
    without them the render half-failed silently (no `pi.json`) and
    first-run's `theme.sh` aborted `omarchy-provision-user` before it set
    the default browser. The ux VM test caught this.
  - Runtime deps: `curl` is added (weather and Elsewhen panels), and
    `socat` is now on the sleep-lock unit PATH as well
    (`omarchy-shell` talks to the shell's own socket).
  - ux VM test: upstream's overlays (menu, OSD, clipboard, emoji) now
    stay mapped as a 1x1 bottom layer when hidden (#13419), so the layer
    probe and the OSD render guards check for a shown (>1x1) surface
    instead of namespace presence. The notification OCR reads both a
    `-normalize` and an `-auto-level` crop, because OWE's black
    background under llvmpipe defeats `-normalize` alone. The manual
    `tests/probe-quickshell-reload.nix` gets the same shown-OSD check, and
    its documented invocation now allows obsidian (the default app set is
    unfree-gated per package, so it no longer evaluated). Re-run: PASS on
    the pinned quickshell.
  - The runtime manifest classifies `omarchy-install-hermes-cli`
    (user-scope `systemctl --user`). Ten new migrations are classified,
    and the ux QML exec baseline goes 124 → 134.
  - herdr 0.8.0 → **0.9.1**, now built from herdrdev/herdr (the project
    moved from omacom-io; Omarchy's PKGBUILD follows it) with Zig 0.16,
    mirroring upstream's `nix/package.nix`. The new Herdr theme sync
    (`omarchy-theme-set-herdr-machines`, menu toggle) needs its
    `herdr machine` subcommand.
  - `omarchy-update-pkg-prune`'s note no longer recommends
    `nix-collect-garbage -d`, which deletes every rollback. It points at
    `nix.gc` / `--delete-older-than` instead.

## 2026-09-19 (2)

- **omp fix**: the packaged `omp` was silently plain Bun. The release ELF
  is a bun single-executable-application whose appended payload is
  offset-keyed, and `autoPatchelf`'s ELF rewrite (≈ +1 KiB, payload
  shifted) made the embedded entry undiscoverable — `omp --version`
  printed Bun's `1.4.2` and `omp` printed bun's help. Found on the test
  VM minutes after a fresh Menu → AI → omp install (the rebuild and
  profile link were fine; the app never loaded). The derivation now
  ships the release binary byte-identical (`dontStrip`, `dontPatchELF`,
  stored under `libexec/`) and `bin/omp` is a `makeWrapper` shim that
  invokes it through the nixpkgs glibc loader explicitly — verified:
  `omp/18.2.6`, proper CLI help, payload sha256 identical to the
  release artifact. A `doInstallCheck` gate now fails the build if
  `omp --version` ever answers with anything but omp's own version.

## 2026-09-19

- Upstream bump `b679363` → `60663fa` (2026-09-19, 41 commits). The
  headline change is **Elsewhen**, the world clock shell plugin, now a
  default bar widget upstream. On Arch it arrives as the `elsewhen`
  package installing `/usr/share/omarchy/plugins/omacom.elsewhen`, with
  the tree's `config/omarchy/plugins/omacom.elsewhen` symlink seeding
  `~/.config/omarchy/plugins/` and migration `1789581661` linking +
  placing it for existing homes. The port keeps every piece of that
  shape: `pkgs/elsewhen.nix` builds the same release the upstream
  PKGBUILD pins (omacom/elsewhen v1.0.0) into
  `$out/share/omarchy/plugins/omacom.elsewhen`, the tree symlink is
  retargeted from `/usr/share/...` to the in-package plugins root, the
  home-manager module manages `~/.config/omarchy/plugins/omacom.elsewhen`
  as a force link refreshed to the active generation every switch (real
  dirs are relocated like the agent-skill links, never deleted), and
  migration `1789581661` runs as an adapter: plugin link + bar
  placement kept, `omarchy-pkg-add` dropped. One deliberate deviation:
  the adapter skips `omarchy-shell shell rescanPlugins` when no shell is
  live — the login-time `omarchy-migrate` unit runs before the session,
  and an unconditional rescan would leave the migration pending forever
  (an absent shell scans `~/.config/omarchy/plugins` at startup anyway;
  a failing rescan on a live shell still fails the migration like
  upstream). Fresh installs get the new default `shell.json` (Elsewhen
  before the center clock) through the existing seed; the widget needs
  `python3` on the session PATH, which the module already ships.

- TCP congestion control: upstream switched to **BBR with fq pacing**
  (`etc/sysctl.d/99-omarchy-sysctl.conf`, migration `1789294350`). The
  module's `boot.kernel.sysctl` block gains
  `net.ipv4.tcp_congestion_control = "bbr"` and
  `net.core.default_qdisc = "fq"` (setting the sysctl autoloads
  `tcp_bbr`/`sch_fq`), and `checks.omarchy-etc-parity` pins both keys.
  The migration itself is `skip` — `nixos-rebuild` applies the keys at
  activation and boot (same doctrine as 1784961000).

- New upstream `bin/omarchy-install-chromium-claude` (called
  best-effort by `omarchy-default-agent` after picking Claude) seeds the
  Claude browser extension's external-update JSON into
  `/usr/share/{chromium,google-chrome,microsoft-edge}/extensions/` —
  `/usr/share` does not exist on NixOS and extension policy is
  module-owned, so it is a `declarative-note` stub pointing at
  `programs.chromium.extensions`.

- PHP/Laravel dev environments: upstream rewrote `install_php` to pure
  mise + Composer (`github:nunomaduro/static-php-builds`, all under
  `$HOME`). The port's `/etc/php` mutation-deletion patch (the anchored
  line-range delete of the php.ini/xdebug.ini block) is obsolete and
  removed; `omarchy install dev-env php|laravel|symfony` now runs the
  upstream mise flow verbatim, and the menu guards follow the new
  `~/.local/share/mise/installs/php` paths.

- Migration classification wave:
  `1789294350` (BBR sysctl live-apply) `skip`,
  `1789325478` (linux-omarchy default kernel + Limine BOOT_ORDER) `skip`,
  `1789444024` (DKMS kernel-headers repair) `skip`,
  `1789581661` (Elsewhen) `adapter` — kernels and boot entries are
  `boot.kernelPackages`/`boot.loader.*` on NixOS.

- Version sweep of the in-repo pinned apps: **zcode-desktop** 3.11.2 →
  3.14.0 (the official downloads page is the version source of truth —
  the AUR `z-code-bin` package lags releases and still pinned 3.12.3
  when 3.14.0 shipped; the bump note in the derivation now says so),
  **claude-desktop** 1.52386.3 → 2.2553.1 (the vendor's stable index
  moved to 2.x; the deb's inner layout and the launcher anchor are
  unchanged), **omp** 18.1.18 → 18.2.6, **omacut** 0.2.0 → 0.4.0,
  **omawrite** 0.4.0 → 0.5.0, **tensaku** 0.26.6 → 0.29.0 (0.29 adds
  input handling that links `libxkbcommon` directly — added to
  buildInputs — and one upstream unit test asserting exact TIFF encoder
  bytes fails in the sandbox, so it is skipped by name; the capture/edit
  flow still exercises the encoder end-to-end in `checks.omarchy-ux`),
  **try** 1.9.3 → 1.10.1, **omarchy-nvim** 2026.7.27 → 2026.8.13 (the
  omarchy-pkgs rev moves; the LazyVim starter rev is unchanged — still
  `main`'s head), **omarchy-fish** → quattro-bash-parity 2026-09-19
  (b1c8639 → 2fe53fa: the fork tip gained the `mup` completions commit
  and a cherry-pick of upstream PR omacom/omarchy-fish#11 — the bashrc
  template sourced the Omarchy-3.x path
  `~/.local/share/omarchy/default/bash/rc`, which does not exist on 4.x,
  silently dropping every Omarchy alias in nested bash; the fix sources
  `$OMARCHY_PATH/default/bash/rc`, which works as-is on NixOS, while the
  PR's guarded env-bootstrap line no-ops here exactly as the port
  intends), and **yaru-theme** 25.10.3 → 26.10.3 (26.10 wires
  `glib-compile-schemas` into the meson install scripts unconditionally
  while shipping no schemas, so the derivation pre-creates an empty
  schemas directory).

- Held back deliberately: **aether** stays 4.28.0 — upstream ships no
  frontend lockfile and the offline npm resolution drifts between the
  `fetchNpmDeps` cache and the build-time resolve (`xmlchars-2.2.0`
  requested but not cached), so the 4.29.9 bump needs its own fix
  rather than a hash dance. **codex** stays 0.146.0 — it resolves from
  the pinned `nixos-26.05` channel (the fresh channel carries the same
  version; `nixos-unstable` has 0.154.0 vs 0.155.1 upstream), and the
  stable-nixpkgs input policy means it moves with the channel, not
  ahead of it.

- Vendored security fixes that flow in unchanged: the Windows VM's RDP
  password no longer appears in the client's argument list,
  screen-recording state and the debug log moved out of world-writable
  `/tmp` into `XDG_RUNTIME_DIR`/`XDG_STATE_HOME`,
  unsafe project-`bin/` PATH injection removed, `omarchy-hook` /
  `omarchy-hook-install` / `omarchy-state` refuse path-like names, and
  the factory reset scrubs old password hashes. `omarchy up` (alias for
  `omarchy update`) works through the vendored dispatcher as-is.

## 2026-09-14

- `omarchy-nix-search` (Install → Package) now searches **NixOS options**
  next to nixpkgs packages: one picker, `pkg` and `opt` rows, over the
  option set of this machine's own nixpkgs — the module pins
  `nix.nixPath` to the running system's source (mkDefault), so the index
  cannot offer an option this system cannot evaluate, and it rebuilds
  when that nixpkgs version changes. Option picks get an honest value
  prompt (true/false, enum choice, validated JSON otherwise — anything
  JSON cannot express is skipped with its metadata, never guessed) and
  land through the same locked transaction as packages:
  `omarchy-nix-add opt:<path>=<value>` writes `omarchy-options.json`
  plus a generated-once `omarchy-options.nix` loader with hash-checked
  rollback of the pair; `omarchy-nix-remove` lists option paths too. The
  fold lives in the loader, not the module, because the module system
  forbids config whose key set depends on data (infinite recursion,
  verified); consumers enable it with one `pathExists`-guarded import
  (README). Two new checks: `omarchy-managed-options` proves the
  generated loader folds picks into a real NixOS evaluation (bool/list,
  empty no-op, conflict-throws), and the transactions check verifies the
  loader against its golden template byte-for-byte, options-only ops
  never creating a packages JSON, and pair rollback. Also fixed en
  route: the add/remove no-op detection compared `jq -cS` outputs with
  unquoted `[[ == ]]` — bash pattern-matches the right side, JSON's `[]`
  form character classes, and the "already installed" short-circuit
  never fired in bash (now quoted; behavior: genuine no-ops skip their
  rebuild again).

- Install → Development → Rust now yields the whole toolchain, not just
  the compiler: `rustfmt` and `clippy` join `rustc` and `cargo` in the
  catalog entry. Arch ships one `rust` package with
  formatter and linter included; nixpkgs splits them across attributes,
  so the menu gave a compiler whose `cargo fmt`/`cargo clippy` failed
  with "no such command". The four attributes cover every binary in
  Arch's `rust` (plus `git-rustfmt` and `rustfmt-format-diff`) and
  cannot drift from the compiler — `rustfmt.nix` and `clippy.nix` both
  inherit `version src` from `rustc`. `rust-analyzer` stays out: on Arch
  it is a separate package. Existing installs keep the old set and the
  Install row stays hidden (the guard sees `rustc`/`cargo` in
  `omarchy-packages.json`), so gaining the two binaries takes one manual
  step: Remove → Development → Rust, then Install again.

## 2026-09-13

- ZCode (Z.ai) joins the Install → AI menu. The app ships
only as a vendor .deb, so it is packaged in-repo
(`pkgs/zcode-desktop.nix`, unfree) and addressed through
`omarchy.ownedPackages`, like Claude Desktop and omp. Its menu entry
carries the app's own mark: the vendored icon font stops at `U+E90E`, so
this repo traces the official app icon and injects `U+E90F` at build time
(`pkgs/omarchy-icons/`), guarded by a new `checks.omarchy-icon-font`.

- upstream refresh to `b679363` (27 commits past the
`31bd80da` refresh; still quattro post-v4.0.3, no new upstream tag).
Pacman transactions now run through a PID-1 `systemd-run` scope wrapper
upstream (`omarchy-update-pacman`, shielding the transaction from
desktop-session teardown) — every caller is already stubbed or replaced
here, so the new script is stubbed with them. Upstream's power-profile
OSD polls D-Bus instead of shelling out, and the Plymouth prompt
re-centers when a display appears late — both vendored as-is. The kyber
I/O-scheduler udev rule for whole disks is classified `native` and
declared via `services.udev.extraRules`. Two new migrations skip: the
Panther Lake kernel swap (Arch kernel/boot machinery) and a Cloudflare
CLI mise wrapper (the mise model is rejected here). Upstream moved its
own GitHub URLs to `omacom/omarchy`; the flake input stays
`github:basecamp/omarchy/quattro` (the redirect works).

- `omarchy update` now rebuilds with `boot`, not
`switch`, by default (ported from mirror PR #7 with authorship
preserved; fixes mirror issue #6). A `switch` on a large nixpkgs jump
legitimately restarts the user session (pipewire, portals, uwsm
plumbing), which killed the updater itself — it runs attached to a
terminal inside that session — and silently skipped every
post-rebuild step (migrations, post-update hooks, status, the reboot
prompt). `boot` never touches running units, so the update flow
completes and the reboot prompt applies the generation atomically;
`OMARCHY_NIX_REBUILD_CMD=switch` restores live activation, and
`omarchy-nix-add`/`omarchy-nix-remove` keep `switch` (their delta
rarely restarts the session). A notice after the rebuild surfaces the
boot-pending state. `OMARCHY_PATH`/`PATH` session entries now point at
the stable system-profile path instead of a store path (the mirror
issue #6 follow-up): every lookup re-resolves the active generation —
upstream's `/usr/share/omarchy` semantics — so after a `switch` the
update flow's post-rebuild steps (`omarchy-migrate`, post-update
hooks) see the new migration set and scripts immediately instead of
the stale login-time tree. The quickshell menu guard batch also
reflects installs now: its `omarchy-pkg-present` shadow was backed by
`pacman`, which does not exist on NixOS, so every Install row stayed
offered (Rust, browsers, …) and Remove rows never appeared no matter
what was installed. The shadows delegate to the NixOS probe binary
(memoized per batch), and a new `omarchy-menu-guards` check executes
the real batch against a fixture consumer state so this cannot drift
again.

## 2026-09-12

- upstream refresh to `31bd80da` (11 commits past the
v4.0.3 pin; no new upstream tag, so this is still quattro post-v4.0.3):
the Claude Desktop app pair and a T3 Code theme re-stage migration.
Both apps now actually install on NixOS: Claude Desktop is packaged
from Anthropic's own Debian package (`pkgs/claude-desktop.nix` — the
same vendor-artifact approach upstream's Omarchy package repository
takes; unfree; the nixpkgs packaging is pending in #537215), and T3
Code comes from nixpkgs itself (MIT, built from source). Two more AI
menu gaps closed: Oh My Pi (omp) ships its release binary, and the
Hermes agent comes from Nous Research's own flake — both now
installable and selectable as the default agent. A new
`omarchy.ownedPackages` option lets Install-menu entries address
derivations packaged in this repository when nixpkgs does not carry
them. The rest of the wave rides along: Hermes desktop install fixes + a portrait icon
in the icon font (vendored as-is), `basecamp-cli` as a lazy mise tool
(skipped — the mise model is rejected here), and a KEF LSX II LT USB
no-suspend WirePlumber config (migration `user-safe`, plus a seed for
fresh installs). Plus a community contribution landed (ported from
the mirror with authorship preserved): `omarchy-shell`/`qs`/`jq` on
the `omarchy-sleep-lock` unit PATH — until then the lock request
never reached the shell, so logind suspended the session unlocked
after `InhibitDelayMax`
([#5](https://github.com/zicochaos/omarchy-nix/pull/5)).

## 2026-09-08

- upstream `v4.0.3` (103 commits since our previous
pin): mostly security backports (plugin-auth boundary, USB device
names as Hyprland Lua, FIDO2 authfile staging, theme-name shell
syntax, webapp escaping, DNS helper PATH pinning, nopasswd sudo
expiry failing closed). Feature side: new AI menu entries — OpenClaw
(kept, rewired to the catalog; the nixpkgs package is MIT but flagged
insecure, entry-scoped permit like bitwarden's electron), Perplexity +
Cursor CLI + Muse Code (dropped: no nixpkgs attrs on the pin; the
nixpkgs `muse` is the MusE audio sequencer, a name collision). Kitty's
base defaults moved to `etc/xdg/kitty/kitty.conf` (vendored via
`environment.etc`, the user seed became a thin override file), native
video wallpaper playback (`qt6.qtmultimedia`), `mise` → `mise-bin`
upstream (no port change — the mise model is rejected here), and an
icon-font retirement. QML exec baseline 122 → 124 (fingerprint
pre-check in the lock plugin — gracefully inert without fprintd — and
a `powerprofilesctl get` reader in the battery service). 9 migrations
classified, 3 new etc/ files, 11 new bin scripts.

## 2026-09-05

- upstream `v4.0.2` (v4.0.1 + v4.0.2, 240 commits): the
security wave — sshd/Plymouth/CUPS/Windows-VM hardening, notification
click actions run as argv (no shell strings), passwordless-root sudoers
grants removed (asdcontrol), automatic printer discovery dropped — plus
the Hermes agent, Antigravity replacing Gemini, webp theme backgrounds,
and `vi` as a standard editor. First community contributions landed
(ported from the mirror with authorship preserved): nested nixpkgs attr
paths in `omarchy-packages.json` (`kdePackages.dolphin`), NixOS
application dirs in `omarchy-launch-webapp`, and NetworkManager ordered
before the graphical session.

## 2026-08-18

- upstream `v4.0.0` (+33 fixes): script renames
(`setup-*` → `apply-*`, `finalize-user` → `provision-user`,
`launch-agent` → `agent`), the agent skill moved to
`default/agents/skills/`, new upstream-owned binaries `ttfx` (Rust TTE
port) and `herdr` (Zig+Rust) packaged, 27 migrations classified.

## 2026-07-28

- behavioral-parity milestone: the full desktop verified
on real hardware; the VM acceptance suite (`checks.omarchy-ux`) green.
