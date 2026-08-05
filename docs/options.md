# `omarchy.*` option reference

All options live under the `omarchy.*` namespace and are declared in
[`config.nix`](../config.nix). They are shared by the NixOS module
([`modules/nixos/default.nix`](../modules/nixos/default.nix)) and the
Home-Manager module ([`modules/home-manager/default.nix`](../modules/home-manager/default.nix)):
set them once at the system level, and the HM layer reads them from
`osConfig.omarchy`.

## Enable / package

### `omarchy.enable` *(bool, default `false`)*

Opt-in switch for the Omarchy system integration: the vendored upstream tree
on the system profile, `OMARCHY_PATH`, the Quattro runtime dependencies, the
uwsm-managed Hyprland session, default SDDM, PipeWire/NetworkManager/Bluetooth
daemons, Plymouth boot splash, and the SDDM login theme. Importing the module
is side-effect-free until this is `true`.

### `omarchy.package` *(nullOr package, default `null`, injected by the flake)*

The vendored omarchy derivation (`$out/share/omarchy`). Set automatically by
the flake's `nixosModules.default`; leave `null` to resolve `OMARCHY_PATH`
yourself.

### `omarchy.plymouthPackage` *(nullOr package, default `null`, injected by the flake)*

The `plymouth-omarchy-theme` derivation. Set automatically by the flake when
`omarchy.plymouth.enable` is true.

### `omarchy.sddmPackage` *(nullOr package, default `null`, injected by the flake)*

The `sddm-omarchy-theme` derivation (login theme + Hyprland greeter config).
Set automatically by the flake when `omarchy.sddm.theme` is true.

### `omarchy.appPackages` *(listOf package, default `[]`, injected by the flake)*

Upstream-owned Omarchy packages packaged by this flake because they are
absent from nixpkgs: aether, asdcontrol, omacalc, omacut, omawrite,
tensaku, try, yaru-theme, hyprland-guiutils,
hyprland-preview-share-picker, omarchy-nvim. Set automatically by the
flake's `nixosModules.default`; override to trim or extend the set.
Entries are still subject to `omarchy.exclude_packages` filtering.

### `omarchy.nvimPackage` *(nullOr package, default `null`, injected by the flake)*

The `omarchy-nvim` derivation (LazyVim starter + omarchy overlay). The HM
module runs its `omarchy-nvim-setup` script once to seed `~/.config/nvim`
as writable copies (mutable seed-and-release, like the other user config
stubs). Set automatically by the flake; `null` skips nvim config seeding.

## Shell

### `omarchy.fish.enable` *(bool, default `false`)*

Install Fish and the vendored Omarchy Fish profile (`omarchy-fish`, pinned
`1.5.0-unstable-2026-07-31` — the fork rev carrying
[omacom-io/omarchy-fish#7](https://github.com/omacom-io/omarchy-fish/pull/7)
— + fzf.fish v10.3): sets `programs.fish.enable` and adds the package
to the system profile, whose `share/fish/vendor_*` directories Fish reads
automatically. Does NOT change any account's login shell; that stays an
explicit per-account setting (`users.users.<name>.shell = pkgs.fish`). Off
by default; the Bash profile is untouched either way. User functions in
`~/.config/fish/functions/` override the vendor ones.

### `omarchy.fish.package` *(nullOr package, default `null`, injected by the flake)*

The omarchy-fish derivation (vendor profile + `omarchy-setup-fish`
informational stub). Set automatically by the flake's
`nixosModules.default`; override to pin a different omarchy-fish revision.
`null` with `omarchy.fish.enable = true` fails evaluation with an
assertion.

## Personal settings

### `omarchy.full_name` *(strMatching `[^\r\n]*`, default `"Omarchy User"`)*

Main user's full name. Used by git and the shell. CR/LF is rejected at
evaluation time: the value lands in `environment.d(5)` and `/etc/profile`,
where a raw newline could forge a second env assignment. Values
are environment.d-escaped (`$` → `$$`, `\` → `\\`, `"` → `\"`) when written
to `/etc/environment.d/50-omarchy.conf`; an empty value is omitted there
(the systemd generator rejects empty assignments).

### `omarchy.email_address` *(strMatching `[^\r\n]*`, default `"omarchy@example.com"`)*

Main user's email address. Used by git. Same CR/LF rejection and
environment.d escaping as `omarchy.full_name`.

### `omarchy.timezone` *(str, default `"Etc/UTC"`)*

System timezone (IANA name). Example: `"Europe/Warsaw"`.

## Desktop

### `omarchy.theme` *(strMatching `[A-Za-z0-9._-]+`, default `"ethereal"`)*

Default Omarchy theme name. Must match a directory under upstream `themes/`
(or a user theme under `~/.config/omarchy/themes/<name>/`). The 22 stock
themes: `catppuccin`, `catppuccin-latte`, `ethereal`, `everforest`,
`flexoki-light`, `gruvbox`, `hackerman`, `kanagawa`, `last-horizon`, `lumon`,
`lupine`, `matte-black`, `miasma`, `nord`, `osaka-jade`, `retro-82`,
`ristretto`, `rose-pine`, `solitude`, `tokyo-night`, `vantablack`, `white`.

Left as a free-form string (not an enum) so users can drop their own theme
under `~/.config/omarchy/themes/<name>/`. The character whitelist permits
every upstream theme name while blocking path traversal (`../`) and newline
injection; the name is interpolated into filesystem paths and shell
commands by the theme engine.

Seed semantics: rendered only on the first Home-Manager activation, when
`~/.local/state/omarchy/current/theme.name` does not exist. Later changes
to this option are no-ops until you edit/remove that file (or run
`omarchy-theme-set <name>` directly). A theme that fails to render (typo,
or a user theme that cannot exist before first activation) only warns
during activation instead of failing the whole switch.

### `omarchy.terminal` *(strMatching `[A-Za-z0-9._-]+`, default `"foot"`)*

Default terminal desktop entry, resolved through `xdg-terminal-exec`. One of
`foot`, `ghostty`, `alacritty`, `kitty`. Same character whitelist as
`omarchy.theme`: the value is written raw (one entry per line) into
`/etc/xdg/hyprland-xdg-terminals.list`, so a newline would forge extra
entries.

### `omarchy.monitors` *(listOf str, default `[]`)*

Hyprland monitor directives, written to `~/.config/hypr/monitors.lua` in the
Lua `hl.monitor({})` table format upstream uses. Empty lets Hyprland
auto-detect (catch-all `output = ""` only). The catch-all and the
`omarchy_gdk_scale` / `omarchy_monitor_scale` locals are always present so
upstream runtime tooling (`omarchy-hyprland-monitor-scaling`) can persist
user scaling changes. Example: `[ "DP-1, 2560x1440@120, 0x0, 1" ]`.

Seed semantics: written only on the first Home-Manager activation, when
`~/.config/hypr/monitors.lua` does not exist. Later changes to this option
(and to `omarchy.scale`) are no-ops until you edit/remove that file.

Entries are validated and Lua-escaped at evaluation time
(`modules/lib/omarchy-formats.nix`): fields are
`output, mode, position, scale, transform` (max 5, everything after output
optional), mode must be `WIDTHxHEIGHT` or `WIDTHxHEIGHT@RATE` (or the
`preferred`/`highres`/`highrr` keywords), position
must be `XxY` integers or `auto`/`auto-*`, scale must be a number or
`"auto"`, transform must be `0`-`7`.
A malformed entry fails the build with a clear error instead of writing a
`monitors.lua` Hyprland cannot parse; quotes/backslashes/newlines in names
can no longer break out of the Lua string literal.

### `omarchy.scale` *(enum `[ 1 2 ]`, default `1`)*

Display scale factor. `1` for 1x displays, `2` for 2x (HiDPI). Drives the
generated `monitors.lua`: scale 1 → `GDK_SCALE=1`, monitor scale `auto`;
scale 2 → `GDK_SCALE=2`, monitor scale `1.2`. An enum, not a free int: the
template only knows these two scale profiles, so any other value now fails
evaluation with a clear error instead of silently generating a nonsense
config.

## Packages

### `omarchy.exclude_packages` *(listOf str, default `[]`)*

Package attribute names to exclude from the default runtime set, so a
consumer can opt out of e.g. obsidian or signal-desktop without forking the
module. Example: `[ "obsidian" "signal-desktop" ]`.

Exact semantics: the filter applies to the **top-level entries** of the
module's own package lists (the runtime-dependency set and
`omarchy.appPackages`), matched by each derivation's `pname` (falling back
to `name` with the version suffix stripped). It is **not** closure
subtraction: excluding a package does not remove it when something else
pulls it in as a dependency, and names of transitive dependencies do not
match anything. Use the attribute name as nixpkgs exposes it (e.g.
`"foot"`, `"ghostty"`).

### `omarchy.managedPackagesFile` *(nullOr path, default `null`)*

Path to the menu-managed package list (`omarchy-packages.json`) written by
the Install/Remove menu actions (`omarchy-nix-add/remove`). When set, the
module folds the JSON's `packages` into `environment.systemPackages` and
its `features` into the matching feature blocks (steam, tailscale,
1password, ollama, …) at evaluation time, so menu installs are declarative
and rollback-safe. `null` disables menu-managed packages.

There is no filesystem auto-detection: flake evaluation is pure, so
`builtins.pathExists` cannot see absolute paths outside the flake
(`/etc/nixos/omarchy-packages.json` is invisible). Point this at the JSON
**inside your own flake**:

```nix
omarchy.managedPackagesFile =
  if builtins.pathExists ./omarchy-packages.json
  then ./omarchy-packages.json
  else null;
```

Fail-closed: a non-null path that does not exist (or is not valid JSON)
fails evaluation with an error naming the file — a silent fallback to
empty sets would drop menu-installed packages on the next rebuild. The
`pathExists` guard form above is the recommended way to express "not
installed yet".

For git-based flakes the add/remove scripts register the JSON with
`git add -N` so the flake snapshot includes it. Where the scripts write:
one shared resolver, `$OMARCHY_NIX_FLAKE` (a flake directory **or** the
path to its `flake.nix` file; an invalid explicit value fails closed,
never falls back to another checkout) → `~/omarchy-nix` →
`~/Projects/omarchy-nix` → `/etc/nixos` (first candidate providing
`nixosConfigurations."$(hostname)"` wins; a candidate is skipped only
when its `nixosConfigurations` evaluate cleanly without the host entry,
i.e. library clones, while eval failures keep it). The JSON lands at
`<flake_dir>/omarchy-packages.json` (see README /
docs/install.md for the full resolver contract).

## System

### `omarchy.binfmtEmulatedSystems` *(listOf str, default `[]`)*

Foreign architectures to execute via qemu-user binfmt registration, wired to
`boot.binfmt.emulatedSystems`. Upstream omarchy installs
`qemu-user-static-binfmt` unconditionally on Arch, so cross-arch docker
builds (`docker buildx --platform linux/arm64`) work out of the box. On
NixOS emulation is strictly opt-in: the default `[]` registers
no handlers and adds no qemu-user closure. Entries are NixOS system strings;
invalid ones are rejected by `boot.binfmt.emulatedSystems`' own enum at
evaluation time. A consumer's own `boot.binfmt.emulatedSystems` assignments
merge with this list.

```nix
omarchy.binfmtEmulatedSystems = [ "aarch64-linux" ];
```

Removing entries and rebuilding unregisters the handlers (rollback-safe).

## System theme

### `omarchy.plymouth.enable` *(bool, default `true`)*

Enable the Omarchy Plymouth boot-splash theme (the splash that runs from
initrd to display-manager). Sets `boot.plymouth.theme` to `"omarchy"` and
adds the vendored theme package. Disable to keep the host's existing boot
splash.

### `omarchy.sddm.theme` *(bool, default `true`)*

Apply the Omarchy SDDM login theme and Hyprland greeter config. Sets
`services.displayManager.sddm.theme` to `"omarchy"` and points the Wayland
greeter `CompositorCommand` at Hyprland with the vendored greeter Lua
config. Only effective when the module's default SDDM is enabled
(`services.displayManager.sddm.enable`). Disable to keep the host's existing
SDDM theme.

## Login UX

### `omarchy.autologin.user` *(nullOr str, default `null`)*

Username to auto-login at the SDDM greeter into the Hyprland (uwsm) session.
`null` (default) keeps the SDDM password prompt. The module wires the NixOS
`services.displayManager.autoLogin.{enable,user}` + `defaultSession =
"hyprland-uwsm"` + `sddm.autoLogin.relogin` from this one knob. Note that
`relogin = true` mirrors upstream: after logging out you are signed
straight back in — the greeter is unreachable for switching users without
unsetting this option (and restarting the display manager).

**LUKS single-password flow:** on an encrypted (LUKS) install, the user
already typed a passphrase to unlock the root disk at boot, so a second SDDM
prompt is redundant friction. Set `omarchy.autologin.user` there to mirror
upstream omarchy's single-password Arch UX: unlock the disk at boot, land
directly on the desktop. The user must exist and be PAM-permitted for
`sddm-autologin` (which NixOS enables when `autoLogin.enable` is set).

Note: this option only controls SDDM autologin; it does NOT configure LUKS
itself. LUKS partitioning/unlocking is the user's bootstrap decision (their
`hardware-configuration.nix` + `boot.initrd.luks`); this just makes the
combination sensible when they did encrypt.

```nix
# On a LUKS install, after the user typed the disk passphrase at boot:
omarchy.autologin.user = "alice";   # lands directly on the desktop
```

## Lock screen

The Quickshell lock screen authenticates through two PAM services declared by
the module: `omarchy-lock-password` (always present, upstream's faillock +
pam_unix stack) and `omarchy-lock-fingerprint` (opt-in below). Upstream writes
these files imperatively via `omarchy-setup-lock`; on NixOS they are
declarative; the three upstream runtime writers
(`omarchy-setup-lock`, `omarchy-setup-security-fingerprint`,
`omarchy-remove-security-fingerprint`) are stubs that print a pointer here.
Override the policy with `lib.mkForce` on
`security.pam.services.omarchy-lock-{password,fingerprint}.text`.

### `omarchy.fingerprint.enable` *(bool, default `false`)*

Enable fingerprint authentication for the lock screen: turns on
`services.fprintd` and declares the `omarchy-lock-fingerprint` PAM service
(`auth required pam_fprintd.so`). Mirrors upstream, where the fingerprint
service exists only after the user enrolls a finger.

```nix
omarchy.fingerprint.enable = true;
# after rebuild, enroll per user:
#   fprintd-enroll
```
