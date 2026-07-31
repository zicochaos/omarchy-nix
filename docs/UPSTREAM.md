# Upstream Omarchy: philosophy and where this port differs

Read this before changing anything that affects "what the user sees".
The port's job is to reproduce upstream behavior; the diffs below are
either deliberate NixOS-isms or known gaps, not features.

## What Omarchy is (from upstream)

Omarchy is DHH's "Beautiful, Modern & Opinionated Linux", a Wayland
desktop distribution, currently on the Quattro generation
(`4.0.0.alpha`, the `quattro` branch is upstream's default). This port
tracks that branch via the `omarchy-src` flake input.

The README on GitHub is intentionally minimal ("Read more at
[omarchy.org](https://omarchy.org)"). The real philosophy is in the
repo:

- **One quickshell process is the desktop.** Bar, launcher, menus,
  notifications, OSDs, control panels, lock screen, polkit agent, all
  plugins of a single long-running `quickshell -n -p
  $OMARCHY_PATH/shell`. Waybar/wofi/mako/hyprlock/hyprpaper/polkit-gnome
  are gone in Quattro.
- **Lua-based Hyprland config (≥0.56).** `~/.config/hypr/hyprland.lua`
  `dofile`s `$OMARCHY_PATH/default/hypr/bootstrap.lua`, then `require()s
  default.hypr.omarchy` (defaults) + `hypr.*` (user overrides).
- **~383 `omarchy-*` bash scripts** in `bin/` do everything. Dispatched
  via the `omarchy` router or called bare from PATH.
- **TOML + sed template theme engine.** `omarchy-theme-set` copies a
  theme's `colors.toml` into a staging dir, runs
  `omarchy-theme-set-templates` (sed over `default/themed/*.tpl`) to
  render 16 per-app configs, atomically swaps the dir into place.

## Upstream's own conventions (`AGENTS.md`)

These are upstream's rules for their code, kept here so port changes
that touch vendored files stay in their style:

- **Two-space indent, no tabs.** Bash 5 conditionals: `[[ ]]` for
  strings/files, `(( ))` for numbers. Inside `[[ ]]`, don't quote
  variables; do quote string literals (`[[ $branch == "dev" ]]`).
- **Shebangs: `#!/bin/bash` consistently**, never `#!/usr/bin/env bash`.
  (NixOS's `fixupPhase` rewrites these to nix-store paths on build.)
- **Command naming**: every command starts with `omarchy-`. Prefixes
  (`cmd-`, `capture-`, `pkg-`, `hw-`, `refresh-`, `restart-`, `launch-`,
  `install-`, `setup-`, `toggle-`, `theme-`, `update-`) indicate
  purpose. The authoritative list is `GROUP_DESCRIPTIONS` in
  `bin/omarchy`.
- **`$OMARCHY_PATH` is the single path source of truth.** Set by the
  uwsm session env; never re-derive from `$HOME` or `shellDir`.
- **Privilege**: use `pkexec` for sudo prompts (so the user gets a
  dialog). Do not use raw `sudo` in scripts.
- **Notifications**: use `omarchy-notification-send`, never raw
  `notify-send`.
- **Helper commands** for package/command checks (`omarchy-cmd-missing`,
  `omarchy-pkg-add`, etc.); see upstream `AGENTS.md` "Helper Commands".
- **Visual changes must be verified in the running UI.** Upstream's
  acceptance tests capture `success-<step>.png` / `failure-<step>.png`
  via QMP virtual keyboard. Creating an artifact is not sufficient;
  inspect it for clipping, overlap, stale state, focus problems.

## Upstream install flow (what we do NOT replicate)

Upstream's `install/` tree owns installation orchestration. It runs
during **ISO chroot finalization**:

- `bin/omarchy-setup-system`: root-owned system setup.
- `bin/omarchy-setup-hardware`: idempotent hardware-specific setup.
- `bin/omarchy-finalize-user`: per-user runtime finalization (skill
  symlinks, xdg-user-dirs, mime defaults, `install/user/all.sh`).
- `install/user/all.sh` runs per-user leaves: `theme.sh`, `chromium.sh`,
  `git.sh`, `xcompose.sh`, `mise.sh`, `default-keyring.sh`, plus
  hardware fixups.
- `install/user/first-run/*.sh` run on first login: voxtype install,
  fingerprint setup, GNOME theme, GTK primary paste, audio tuning,
  welcome/wifi notifications.

**This port does not replicate the ISO chroot orchestration** (it carries
Arch/pacman installer semantics). Instead `install/` is **vendored** and
the per-user parts run for real:
`omarchy-finalize-user` + `install/user/all.sh` run on first login via the
upstream `omarchy-first-run` autostart: pure-config steps (gnome-theme,
gtk-primary-paste, git, xcompose, default-keyring, xdg-user-dirs,
enable-user-units, chromium native-messaging hosts) and genuinely useful
steps (audio-tuning, welcome, wifi, hardware fixups, no-op when the
hardware does not match). The Arch-packaging steps (`mise.sh`,
`mise-work.sh`) are no-op stubs in the package, and only the two
*invitation* hooks (voxtype, fingerprint) are pre-marked done so their
toasts never fire; voxtype itself is shipped declaratively and the
lock-screen PAM services are declared natively. What still does
not run: the root-owned ISO setup (`omarchy-setup-system`,
`omarchy-setup-hardware`); their effects (packages, services, themes) are
declared by the NixOS module instead.

## Upstream defaults (from the vendored source)

These are the defaults encoded in the upstream source (rev `283276be`,
`4.0.0.alpha`, quattro branch). Compare against them when verifying
parity:

- **Theme**: `ethereal` (22 rendered files in `current/theme/`).
- **Terminal**: **foot** (`default/xdg-terminal-exec/hyprland-xdg-terminals.list`
  contains only `foot.desktop`; upstream ships
  `applications/foot.desktop` with `X-TerminalArgDir=--working-directory=`).
  Ghostty is opt-in via `omarchy-install-terminal ghostty` /
  `omarchy-default-terminal ghostty` (writes `~/.config/xdg-terminals.list`
  and copies `config/ghostty/`).
- **Browser**: **chromium** (`bin/omarchy-finalize-user` runs
  `xdg-settings set default-web-browser chromium.desktop`; chromium is
  in `install/omarchy-base.packages`). Upstream also exports
  `BROWSER=omarchy-launch-browser` and `TERMINAL=xdg-terminal-exec` via
  `default/uwsm/default` + `env.d`.
- **Cursor**: upstream sets **no cursor theme**, only sizes
  (`hl.env("XCURSOR_SIZE","24")`, `hl.env("HYPRCURSOR_SIZE","24")` in
  `default/hypr/envs.lua`). No cursor package in
  `install/omarchy-base.packages`; on Arch, Adwaita cursors arrive
  transitively via `gnome-themes-extra`.
- **uwsm launch**: the upstream session entry
  (`default/wayland-sessions/omarchy.desktop`) runs
  `uwsm start -g -1 -e -D Hyprland hyprland.desktop` (the
  `hyprland.desktop` comes from the Hyprland/uwsm packages, not the
  omarchy repo). Our port ships a custom `hyprland-uwsm.desktop` running
  `uwsm start -e -D Hyprland hyprland.desktop`, with the same
  desktop-name semantics (`XDG_SESSION_DESKTOP=Hyprland`, oracle match),
  without the `-g -1` flags (upstream's "new session, one-shot"
  variations).
- **Key bindings** (`default/hypr/bindings/applications.lua`):
  - `SUPER+RETURN` → Terminal (`{ omarchy = "terminal" }`)
  - `SUPER+SHIFT+RETURN` / `SUPER+SHIFT+B` → Browser
  - `SUPER+SHIFT+F` → File manager (nautilus)
  - `SUPER+SHIFT+N` → Editor
  - `SUPER+SPACE` → Omarchy launcher (the shell's launcher, not a
    separate wofi)
  - Plus preinstalled-app and webapp bindings (spotify, signal, obsidian,
    1password, ChatGPT, HEY, YouTube, ...).

## Where this port deliberately differs from upstream

| Area | Upstream | This port | Why |
|---|---|---|---|
| **Tree location** | `/usr/share/omarchy` | `$out/share/omarchy` (nix store) | Nix constraint: nothing mutable in `/usr`. `$OMARCHY_PATH` points here. |
| **Bin on PATH** | `/usr/bin/omarchy-*` (Arch package) | `$OMARCHY_PATH/bin` prepended to session PATH | We chose Approach A (session PATH) over B (top-level `$out/bin/`). The 7 systemd user units that hardcode `/usr/bin/` are path-adapted to store paths in `pkgs/omarchy.nix`, so none are broken. |
| **OMARCHY_PATH source** | `default/bash/env-bootstrap` (sourced by `/etc/profile.d/omarchy.sh`, skel `.bashrc`, `uwsm/env.d/10-omarchy`) | NixOS `environment.sessionVariables` + `environment.etc."xdg/uwsm/env.d/10-omarchy"` | We do NOT source `env-bootstrap`; it carries Arch/pacman dev-link logic. Same effect via NixOS-native channels. |
| **Theme render trigger** | ISO chroot finalization (`omarchy-setup-system`) | HM activation script (`omarchyThemeRender`) | No ISO stage on NixOS; run the same upstream `omarchy-theme-set` in HEADLESS mode during `home-manager switch`. |
| **First-run hooks** | `install/user/first-run/*.sh` on first login | **Runs for real**: `install/` is vendored and `omarchy-first-run` executes on first login | Only the two *invitation* hooks (voxtype, fingerprint) are pre-marked done so their toasts never fire; voxtype ships declaratively, fingerprint PAM is native. The Arch-packaging steps (`mise.sh`, `mise-work.sh`) are no-op stubs. |
| **Per-user setup** | `install/user/all.sh` (theme, chromium, git, xcompose, mise, keyring) | **Runs** via the vendored `omarchy-finalize-user` on first login | `OMARCHY_USER_NAME`/`EMAIL` come from `omarchy.full_name`/`email_address` (environment.d + /etc/profile). Only `mise.sh`/`mise-work.sh` are no-op'd (Arch tarballs under `/opt/packages`, rejected as a feature). |
| **Hyprland package** | Arch `hyprland` package ( pacman) | `hyprland` flake input, self-contained build against its own nixpkgs | Needs ≥0.56 for the Lua config; stable nixpkgs only has 0.55.4. |
| **Hyprland Cachix** | N/A (Arch builds from AUR/cache) | Auto-configured in module (`nix.settings.substituters`) | The flake Hyprland package isn't on cache.nixos.org; without this every consumer rebuilds Hyprland from source (OOMs small VMs). |
| **Terminal default** | **foot** (`hyprland-xdg-terminals.list` → `foot.desktop`; ghostty opt-in) | foot in runtime deps; vendored list + `foot.desktop` installed to the package's `share/`; `/etc/xdg/hyprland-xdg-terminals.list` written from `omarchy.terminal` | The module-level list wins over the vendored fallback, so `omarchy.terminal = "ghostty"` re-points Super+Enter declaratively; an uninstalled choice degrades to foot. |
| **Browser default** | **chromium** (set in `omarchy-finalize-user` via `xdg-settings`) | **chromium**: in runtime deps; `BROWSER=omarchy-launch-browser` in session env; `chromium-browser.desktop` aliased to `chromium.desktop`; `xdg-settings` runs in finalize-user + HM activation | NixOS names the desktop file `chromium-browser.desktop`; upstream tooling expects `chromium.desktop`. |
| **Cursor** | no theme (only `XCURSOR_SIZE`/`HYPRCURSOR_SIZE`=24; Adwaita cursors arrive via `gnome-themes-extra` on Arch) | `adwaita-icon-theme` in runtime deps + a `default → Adwaita` fallback package (`xcursor-default-adwaita`) | Upstream sets no theme NAME, so libxcursor resolves theme "default"; the fallback's `icons/default/index.theme` (Inherits=Adwaita) mirrors the Arch oracle byte-for-byte. No theme name is set, same as upstream. |

## Arch-only surface: classification

Every upstream feature that depends on Arch specifics (pacman, AUR,
ISO-installer stages, snapper/limine) falls into exactly one of these
classes. The script-level inventory is enforced by
`checks.omarchy-runtime` (an unclassified new upstream mutator fails the
build); this table is the feature-level summary.

| Class | Meaning | Items |
|---|---|---|
| **Adapted** | Works, in a NixOS-native form | Install/Remove menu (catalog → `omarchy-nix-add/remove` → `omarchy-packages.json` → rebuild, transactional with audit logs); Update → Omarchy (flake update + `nixos-rebuild switch`); migrations (fail-closed classifier, NixOS adapters); firmware update (`fwupdmgr`); presence checks (`omarchy-pkg-present` via catalog + PATH); first-run / finalize-user (vendored, runs on first login); systemd user units (path-adapted, enabled); lock-screen PAM (declared natively); zram swap (`zramSwap`, upstream's zstd/full-RAM profile); cross-arch execution (opt-in `omarchy.binfmtEmulatedSystems` → `boot.binfmt.emulatedSystems`); sshd key add/remove; `omarchy-update-restart` (compares `/run/{booted,current}-system/kernel`); install-dev-env (without `/etc/php` edits); snapshots (print a NixOS generations note); the three system-level defaults behind skipped upstream migrations (logind `InhibitDelayMaxSec=15` via `services.logind.settings`, `NetworkManager-wait-online` mask, Wi-Fi powersave off via `networking.networkmanager.wifi.powersave`); bundled Chromium extensions (`--load-extension` in the seeded `chromium-flags.conf` path-adapted to `/run/current-system/sw/share/omarchy`, existing user files rewritten by migration adapter `1780517689.sh`) |
| **N/A** | No NixOS analogue; removed or stubbed | AUR (menu entry deleted; `omarchy-pkg-aur-accessible` always exits 1); pacman channels/mirrors (`omarchy-channel-current` prints `nixos`); limine + snapper (systemd-boot + boot generations instead); direct-boot, hybrid-gpu, hibernation-setup, DNS, fido2, passwordless-sudo, plymouth/timezone refresh, sunshine (declarative-note stubs; their menu entries are deleted); pacman keyring/orphans/reinstall helpers; `mise` dev-tool manager (Arch tarballs under `/opt/packages`; `mise.sh`/`mise-work.sh` no-op'd; **rejected** as a feature: the dev menu installs global Nix packages via the catalog, which is the final model) |
| **Deferred** | Possible on NixOS, not done | NordVPN service (menu entry deleted; verified 2026-07-31: the package + `services.nordvpn` already reached the 26.05 channel after our `2f5a153c27` pin — re-add as a catalog feature once the pin reaches a revision carrying both); zen / brave-origin browsers (AUR-only, no nixpkgs attrs on the 26.05 pin; menu entries deleted) |
| **Blocked / untested** | Needs an external precondition | Fingerprint **reader** on real hardware (the PAM services themselves are declared and pamtester-verified in `checks.omarchy-ux`); real-hardware specifics of the behavioral surface; menu IPC, notifications, OSD, lock and polkit are covered in the VM by `checks.omarchy-ux` section (10) since 2026-07-29, but multi-monitor lock, fingerprint dialog and panel interactions still need a real-hardware pass |

## When upstream updates

```bash
nix flake lock --update-input omarchy-src
nix flake check
```

Then re-verify against [§ Upstream defaults (from the vendored
source)](#upstream-defaults-from-the-vendored-source). Upstream
can shift defaults (new terminal, new cursor, new keymap, renamed
scripts, new theme templates); a green `nix flake check` does **not**
mean parity survived.

## Bump checklist

Concrete steps for `nix flake lock --update-input omarchy-src`. The
adaptations already cataloged in `pkgs/omarchy.nix` (its patch comments)
are the authoritative input.

In the commands below, `$SRC` is the upstream source root, either the
flaked source or a checkout of the new `omarchy-src` rev for diffing
against the previous one.

### 1. Bump and build

```bash
nix flake lock --update-input omarchy-src
nix flake check
```

`substituteInPlace --replace-fail` makes vanished patch targets fail
the build loudly. For each failure: fix the pattern, or drop the patch
if upstream changed the approach, and update the comment that documents
the adaptation in the same commit.

### 2. Re-run the mutation-surface greps

These catch new upstream scripts that copy from the store into `$HOME`
or reference Arch-only paths, the two classes that need adaptation.

**New store-to-`$HOME` copies (need `--no-preserve=mode`):**

```bash
grep -rn 'cp ' "$SRC/bin/" | grep '\$OMARCHY_PATH'
```

Compare against the scripts already carrying `--no-preserve=mode` in
`pkgs/omarchy.nix`. Any new match needs
a `--no-preserve=mode` patch or it inherits read-only store modes and
breaks theme swaps / config edits.

**New Arch-only paths (need adaptation or no-op):**

```bash
grep -rn '/usr/\|/etc/pacman\|pacman ' "$SRC/bin/" | grep -v '^.*#'
```

Compare against the Arch-path adaptations already in `pkgs/omarchy.nix`.
New `/usr/bin/` references in systemd
units, new `/usr/share/omarchy` hardcodes, or new pacman calls need
handling.

**Menu actions (new binary deps):**

```bash
diff <(old-rev)/default/omarchy/omarchy-menu.jsonc \
     "$SRC/default/omarchy/omarchy-menu.jsonc"
```

New menu actions may call new `omarchy-*` binaries that need to be on
the runtime dep list. The `checks.omarchy-ux` binary-coverage subtest
catches these automatically; if it goes red, trace the missing binary.

**Systemd user units:**

```bash
diff -rq <(old-rev)/default/systemd/user/ \
         "$SRC/default/systemd/user/"
```

New or changed units under `default/systemd/user/` need `/usr/bin/`
path adaptation and a `wantedBy` decision (match
upstream's `enable-user-units.sh`).

**Omarchy agent skill:**

```bash
diff <(old-rev)/default/omarchy-skill/SKILL.md \
     "$SRC/default/omarchy-skill/SKILL.md"
nix build .#checks.x86_64-linux.omarchy-skill
```

Port relevant runtime guidance into `skills/omarchy/SKILL.md`, but keep
Arch package management, fixed system paths, and source-development
instructions out. Re-check upstream `omarchy-finalize-user` and upgrade
scripts for additions to the four supported agent link paths (wired in
`modules/home-manager/default.nix`).

**Upstream package list:**

```bash
diff <(old-rev)/install/omarchy-base.packages \
     "$SRC/install/omarchy-base.packages"
```

New packages in upstream's list need mapping to nixpkgs (or an
explicit exclusion with rationale).

### 3. Behavioral re-verify

Verify behaviorally (not just processes):

- Theme switch (e.g. `omarchy theme set tokyo-night` then `nord`):
  bar + shell colors change, `colors.toml`/`shell.toml` track the
  theme, no staging debris, all files user-writable.
- Super+Enter opens `foot` (real keypress, not just `hyprctl binds`).
- First-run evidence: `~/.local/state/omarchy/first-run.log` has
  "Completed:" lines, `done/first-run-user` exists, `~/.XCompose`
  present.

`checks.omarchy-ux` covers all three automatically. Run it first; do
manual verification only for areas the test does not cover.

### 4. Commit

One revision = one commit. Include `flake.lock` + any adaptation fixes
from steps 1–2 together. Do not split a bump across commits.
