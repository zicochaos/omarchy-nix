# omarchy-nix

A NixOS port of [basecamp/omarchy](https://github.com/basecamp/omarchy), the
Quattro generation.

Omarchy is DHH's opinionated Linux desktop. As of Quattro, its "desktop" is a
single [quickshell](https://quickshell.org) process: the bar, launcher,
menus, notifications, OSDs, control panels, lock screen, and polkit agent are
all plugins of one long-running shell. It is driven by a Lua-based Hyprland
config (≥0.56) and ~444 `omarchy-*` bash scripts, themed by a TOML + template
engine.

This project ports that to NixOS **by vendoring upstream**, not by
hand-translating it. The upstream `basecamp/omarchy` quattro tree is packaged
as a Nix derivation and wired into a NixOS module + a Home-Manager module, so
the desktop you get is the real Omarchy desktop, not a reimplementation.

## Status

**Vendored Omarchy desktop with automated behavioral coverage.** The port
reproduces the real Omarchy desktop: Hyprland session via uwsm,
quickshell bar/menus, Super+Enter terminal, theme switching with live
colors (not just wallpaper), editable user configs, first-run hooks, the
full upstream package set (including the 13 upstream-owned packages
absent from nixpkgs, packaged under `pkgs/`), and a NixOS-native
`omarchy update` flow. Verified in a running session on real Intel GPU
hardware (2026-07-28). The automated acceptance suite checks the subset
described below on subsequent changes.

Automated NixOS tests run under `nix flake check`:
`checks.omarchy-desktop` (stack comes up), `checks.omarchy-ux`
(behavioral acceptance: Super+Enter opens foot, headless theme rendering,
config editability, and command coverage of menu actions and `when:`/`disabled:` guards,
autostart, and systemd command — `bash -c` interiors and QML exec sites
are guarded by count tripwires), and `checks.omarchy-fish` (vendor
profile parity).

The VM tests start the session from tty1 with SDDM disabled. Theme checks
use headless rendering, and package/update checks skip the real system
rebuild. These tests do not establish live bar/shell color changes, the
SDDM login flow, or a complete update followed by activation. Those paths
still need separate desktop verification after relevant changes.

> Upstream's Quattro line is at `v4.0.3` (2026-09); this port tracks the
> `quattro` branch (release + post-release fixes). The vendored `version`
> file still reads `4.0.0.alpha` — upstream does not bump it at release time.

### Known VM limitation (not a port bug)

`quickshell` crashes with `unknown object (50), message attach` under
VirtualBox's VMSVGA renderer (and likely under QEMU's software
framebuffer) even though Hyprland itself renders. This is a VM
graphics-stack issue, not an omarchy-nix bug: the same config runs
`quickshell` stably on real Intel GPU hardware. Use real metal or a
GPU-passthrough VM for desktop exploration; use the VM only for
module/build verification.

## Changelog

- **2026-09-13** — `omarchy update` now rebuilds with `boot`, not
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

- **2026-09-12** — upstream refresh to `31bd80da` (11 commits past the
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
- **2026-09-08** — upstream `v4.0.3` (103 commits since our previous
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
- **2026-09-05** — upstream `v4.0.2` (v4.0.1 + v4.0.2, 240 commits): the
  security wave — sshd/Plymouth/CUPS/Windows-VM hardening, notification
  click actions run as argv (no shell strings), passwordless-root sudoers
  grants removed (asdcontrol), automatic printer discovery dropped — plus
  the Hermes agent, Antigravity replacing Gemini, webp theme backgrounds,
  and `vi` as a standard editor. First community contributions landed
  (ported from the mirror with authorship preserved): nested nixpkgs attr
  paths in `omarchy-packages.json` (`kdePackages.dolphin`), NixOS
  application dirs in `omarchy-launch-webapp`, and NetworkManager ordered
  before the graphical session.
- **2026-08-18** — upstream `v4.0.0` (+33 fixes): script renames
  (`setup-*` → `apply-*`, `finalize-user` → `provision-user`,
  `launch-agent` → `agent`), the agent skill moved to
  `default/agents/skills/`, new upstream-owned binaries `ttfx` (Rust TTE
  port) and `herdr` (Zig+Rust) packaged, 27 migrations classified.
- **2026-07-28** — behavioral-parity milestone: the full desktop verified
  on real hardware; the VM acceptance suite (`checks.omarchy-ux`) green.

Upstream adaptation details and the bump checklist: [`docs/UPSTREAM.md`](docs/UPSTREAM.md).

## Design rule

**Ship the real Omarchy desktop on NixOS: vendor upstream, do not rewrite it.**

The running desktop is produced by the same code that produces it on Arch
Omarchy: the same quickshell process (`$OMARCHY_PATH/shell/shell.qml`), the
same Hyprland Lua config chain, the same ~444 `omarchy-*` bash scripts, the
same TOML + sed theme engine. The NixOS layer is glue (a vendoring
derivation, two modules, options, activation), not a reimplementation.

When a change is proposed, ask: does the running desktop stay the real
Omarchy desktop, or does this turn the port into a reimplementation? "It
would be cleaner in Nix" is not sufficient reason to deviate.

## Quick start

Add `omarchy-nix` to your flake inputs and import the NixOS + Home-Manager
modules. One `omarchy.enable = true` wires the whole desktop:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    omarchy-nix.url = "github:zicochaos/omarchy-nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, omarchy-nix, home-manager, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        omarchy-nix.nixosModules.default
        home-manager.nixosModules.home-manager
        # The omarchy HM module is shared with all home-manager.users, so
        # per-user blocks only carry user settings (see example/).
        { home-manager.sharedModules = [ omarchy-nix.homeManagerModules.default ]; }
      ];
    };
  };
}
```

> The attribute name must match the machine's hostname: the menu
> Install/Remove actions and `omarchy update` resolve
> `nixosConfigurations."$(hostname)"`. Naming it `my-host` while the host
> is called something else still gives a working desktop, but those
> commands fail with a resolver error (see the resolver contract below).

and in `configuration.nix`:

```nix
{ ... }:

{
  omarchy.enable = true;
  omarchy.full_name = "Your Name";
  omarchy.email_address = "you@example.com";
  omarchy.theme = "ethereal";   # one of the 22 stock themes

  users.users.your-user = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "input" "networkmanager" "ydotool" ];
    # Generate YOUR hash with `mkpasswd -m yescrypt` (nixpkgs#mkpasswd) and
    # paste it here — the value is world-readable in /nix/store, which is
    # safe for a hash but not for a plaintext password.
    initialHashedPassword = "$y$j9T$PASTE-YOUR-HASH-HERE";
  };

  home-manager.users.your-user = {
    home.username = "your-user";
    home.homeDirectory = "/home/your-user";
    home.stateVersion = "26.05";
    omarchy.enable = true;
  };

  system.stateVersion = "26.05";
}
```

The module whitelists the one unfree default app (obsidian) itself, so
`nixpkgs.config.allowUnfree` is not needed. `example/configuration.nix` is a
complete, runnable consumer (wired in-repo as `nixosConfigurations.example`)
you can build as a VM:

```bash
nix build .#nixosConfigurations.example.config.system.build.vm
QEMU_OPTS="-device virtio-gpu-pci" ./result/bin/run-nixos-vm
```

The module enables `services.openssh` by default (`mkDefault`) with
keys-only logins (`PasswordAuthentication` and
`KbdInteractiveAuthentication` default to false). Rationale: applying
omarchy with `nixos-rebuild switch` rebuilds the whole activation from
your config, so if nothing enables sshd, the switch silently removes the
running sshd, which is an unrecoverable lockout on a box you administer
remotely; keys-only keeps a weak or documented local password from being
SSH-able over the LAN. Both are plain `mkDefault`s: set
`services.openssh.enable = false;` on a console-only machine, or
`services.openssh.settings.PasswordAuthentication = true;` if you really
want password logins.

Other security-relevant defaults mirror upstream on purpose:
`nix.settings.trusted-users` includes `@wheel` (every wheel user is a
trusted Nix user, as on Arch Omarchy); `omarchy-tzupdate` gets NOPASSWD
sudo (runtime timezone changes fight the declarative `time.timeZone` —
the rebuild wins); the lock-screen PAM stack keeps upstream's `nullok`
(accounts without a password unlock with an empty one); and SDDM
autologin uses `relogin = true` (see `omarchy.autologin.user` in
[`docs/options.md`](docs/options.md)).

### Installing and updating (the NixOS way)

Super+Space → Install/Remove works the upstream way: pick an entry and the
system rebuilds in front of you. Known catalog entries (browsers, editors,
terminals, gaming, AI, dev toolchains, services) map to opinionated nixpkgs
choices; Install → Package is a free fzf search over nixpkgs. Choices land in
`omarchy-packages.json` next to your flake and are folded into the system
declaratively at rebuild. Removing works the same way. Entries with no
NixOS analogue (AUR, ONCE) are removed from the menu outright; NordVPN
stays out until the pin reaches a revision carrying both the package and
the module (the backport already reached the 26.05 channel); dev-env
entries without a catalog mapping (laravel/symfony/phoenix) show a
declarative note. Update → Omarchy still runs flake update +
rebuild.

One wiring step is required: point the module at that JSON **inside your
flake** (flake evaluation is pure; absolute paths like
`/etc/nixos/omarchy-packages.json` are invisible to it):

```nix
omarchy.managedPackagesFile =
  if builtins.pathExists ./omarchy-packages.json
  then ./omarchy-packages.json
  else null;
```

The `pathExists` guard keeps evaluation working before the first menu
install. For git-based flakes the add/remove scripts register the JSON with
`git add -N` automatically, so the flake snapshot can see it. A non-null
but missing (or unparseable) file fails evaluation loudly with the file
path — silently falling back to empty sets would drop menu-installed
packages on the next rebuild.

All NixOS-specific commands (update, add, remove, presence checks, search)
share one resolver for the consumer flake: `$OMARCHY_NIX_FLAKE` (either a
directory containing `flake.nix` or the path to the `flake.nix` file itself,
which must be named exactly `flake.nix`), then `~/omarchy-nix`,
`~/Projects/omarchy-nix`, `/etc/nixos`. In the fallback order the first
candidate that provides `nixosConfigurations."$(hostname)"` wins. A
candidate is skipped only when its `nixosConfigurations` evaluate cleanly
but have no entry for this host (e.g. a bare omarchy-nix library clone
pulled for updates). An evaluation failure keeps the candidate instead of
silently skipping it. An explicit `OMARCHY_NIX_FLAKE` that is invalid fails
with diagnostics rather than falling back to another checkout.

`omarchy update` rebuilds with **`boot`, not `switch`, by default**: a
`switch` on a large nixpkgs jump legitimately restarts the user session
(pipewire, portals, uwsm plumbing), which kills the updater itself — it runs
attached to a terminal inside that session — and silently skips every
post-rebuild step (migrations, post-update hooks, status, the reboot
prompt). `boot` never touches running units; the reboot prompt at the end of
the update activates the new generation atomically. Set
`OMARCHY_NIX_REBUILD_CMD=switch` to restore live activation for small
updates. `omarchy-nix-add`/`omarchy-nix-remove` keep `switch` — their delta
rarely restarts the session.

### What `omarchy.enable = true` does

System (NixOS module): the vendored upstream tree on the system profile
with `OMARCHY_PATH` set as a session variable (deliberately the stable
system-profile path, so every lookup re-resolves the active generation —
the same semantics as upstream's static `/usr/share/omarchy`; a
store-path value would freeze the tree at login and make the update
flow's post-rebuild steps read stale migrations), the full upstream default
package set from nixpkgs (foot, neovim, btop, lazygit, chromium, nautilus,
libreoffice, obs-studio, kdenlive, dev toolchains, fonts, …) plus the 13
upstream-owned packages packaged by this flake (aether, omacut, omawrite,
omacalc, tensaku, try, asdcontrol, yaru-theme, hyprland-guiutils,
hyprland-preview-share-picker, omarchy-nvim, herdr, ttfx), the parity services
(avahi, printing, docker, gnome-keyring, fwupd, udiskie, …, all
`mkDefault`), a uwsm-managed Hyprland session (≥0.56 for the
Lua config), default SDDM, PipeWire/NetworkManager/Bluetooth daemons, the
Omarchy Plymouth boot splash, and the Omarchy SDDM login theme + Hyprland
greeter.

Per-user (Home-Manager module): seeds `~/.config/hypr/hyprland.lua` (the
entry point that dispatches into `$OMARCHY_PATH`), the user-editable stub
files the entry point `require()`s, the quickshell `shell.json`, the
omarchy-nvim LazyVim starter (`~/.config/nvim`), and the default theme
rendered into `~/.local/state/omarchy/current/theme`, all as mutable
copies: user edits (and upstream tooling writes, e.g. theme switches)
survive rebuilds. It also keeps the package-owned `omarchy` agent skill
linked into Agents, Claude, Codex, Pi, Gemini, and Hermes on every
activation, so links follow the active Nix store generation after
updates. Real, user-owned
files or directories at those link paths are never overwritten:
activation moves them aside to `<path>.hm-backup-<timestamp>` first
(existing symlinks are simply adopted).

See [`docs/options.md`](docs/options.md) for the full `omarchy.*` option
reference, and [`docs/install.md`](docs/install.md) for the "fresh NixOS
minimal install" walkthrough (partition, wire the flake, `nixos-install`,
reboot into the desktop).

### Fish shell (opt-in)

The default shell stays Bash, exactly like upstream. To opt a user into the
vendored [omarchy-fish](https://github.com/omacom-io/omarchy-fish) profile
(+ fzf.fish v10.3):

```nix
omarchy.fish.enable = true;           # installs fish + the Omarchy vendor profile
users.users.alice.shell = pkgs.fish;  # login shell is your explicit account setting
```

Fish picks the profile up from the system profile's `share/fish/vendor_*`
directories; nothing is written to `~/.config/fish`, and functions you place
in `~/.config/fish/functions/` override the vendor ones. The profile carries
the Quattro bash-parity helpers (`cy`, `mup`, `rsw`, `lsw`, `dsw`, `tds`),
the current `omarchy` completion contract and a lazy `try` integration. It
is pinned to the fork rev carrying
[omacom-io/omarchy-fish#7](https://github.com/omacom-io/omarchy-fish/pull/7)
until an upstream release includes that PR.

## Testing

The desktop is verified by an automated NixOS test that runs under
`nix flake check`:

```bash
nix flake check                # runs checks.omarchy-desktop + checks.omarchy-ux + checks.omarchy-fish
nix build .#checks.x86_64-linux.omarchy-desktop.driver   # just the test driver
```

For a manual VM:

```bash
nix build .#nixosConfigurations.demo.config.system.build.vm --out-link result-vm
QEMU_OPTS="-device virtio-gpu-pci" ./result-vm/bin/run-nixos-vm
```

See [`docs/vm.md`](docs/vm.md) for the full VM testing path and known QEMU
limitations.

## Project layout

```
flake.nix              # inputs + outputs (packages, modules, checks, configs)
config.nix             # omarchy.* option schema
pkgs/                  # vendoring + themes + 13 upstream-owned packages:
  omarchy.nix          #   the upstream tree -> $out/share/omarchy
  plymouth-omarchy-theme.nix sddm-omarchy-theme.nix yaru-theme.nix
  aether.nix asdcontrol.nix omacalc.nix omacut.nix omawrite.nix tensaku.nix
  try.nix hyprland-guiutils.nix hyprland-preview-share-picker.nix
  omarchy-nvim.nix omarchy-fish.nix ttfx.nix herdr.nix
  omarchy-catalog.nix  #   Install/Remove menu catalog (nix-catalog.json)
  omarchy-migrations.nix + migrations-nix/  # migration classes + NixOS adapters
  omarchy-etc-manifest.nix omarchy-runtime-manifest.nix  # fail-closed manifests
modules/nixos/         # NixOS module: env, runtime deps, services, Hyprland, themes
modules/home-manager/  # HM module: per-user config seeds (mutable)
skills/omarchy/        # NixOS-native end-user agent skill (packaged + linked by HM)
tests/                 # desktop.nix (stack) + ux.nix (behavioral) + fish.nix
example/               # demo consumer flake
docs/                  # install.md, options.md, UPSTREAM.md, vm.md,
                       # nix-best-practices.md
```

## Updating upstream

```bash
nix flake lock --update-input omarchy-src
nix flake check
```

Commit `flake.lock` together with any adaptation fixes the new upstream rev
requires. One revision, one commit. Follow the full bump checklist in
[`docs/UPSTREAM.md`](docs/UPSTREAM.md); `--replace-fail` patches fail
loudly when upstream shifts under them.

## Contributing

This GitHub repository is the project's **public home**. Development
happens in a separate canonical repository (protected `main`; every
change lands through a PR that must pass CI, including the VM acceptance
tests). After each merge, a squashed snapshot of `main` is published
here — so this mirror's history carries no individual commits or merge
points, and PRs cannot be merged directly on GitHub (the next snapshot
publish would orphan the merge).

**PRs from outside contributors are welcome anyway.** A PR opened here is
**ported to the canonical repository with authorship preserved** — your
commit, your author line, plus a "Ported from mirror PR #N" trailer —
goes through the same CI, and merges like any other PR; the mirror PR is
then closed with a pointer to the landed change. The changelog above and
the credits below record such contributions.

Contributions landed so far:

<!-- Rendered as an explicit table (avatars resolve from GitHub profile
     URLs): GitHub's native "Contributors" list counts committers on the
     default branch, and this mirror only receives squash snapshots
     published under one identity — ported authors would never appear
     there. -->
| Contributor | Landed contributions |
| --- | --- |
| <a href="https://github.com/madebydamo"><img src="https://github.com/madebydamo.png" width="44" valign="middle" alt="@madebydamo" /></a> **[@madebydamo](https://github.com/madebydamo)** | Resolving nested nixpkgs attribute paths from `omarchy-packages.json` ([#2](https://github.com/zicochaos/omarchy-nix/pull/2)); searching NixOS application dirs in `omarchy-launch-webapp` ([#3](https://github.com/zicochaos/omarchy-nix/pull/3)); putting `omarchy-shell`/`qs`/`jq` on the `omarchy-sleep-lock` unit PATH so the lock request reaches the shell before suspend ([#5](https://github.com/zicochaos/omarchy-nix/pull/5)) |
| <a href="https://github.com/VirtualMachinist"><img src="https://github.com/VirtualMachinist.png" width="44" valign="middle" alt="@VirtualMachinist" /></a> **[@VirtualMachinist](https://github.com/VirtualMachinist)** | Ordering NetworkManager before the graphical session, fixing the quickshell network-panel race at session start ([#4](https://github.com/zicochaos/omarchy-nix/pull/4)) |

## License

MIT, same as upstream Omarchy (upstream copyright: David Heinemeier
Hansson and Omarchy contributors). One exception:
[`docs/nix-best-practices.md`](docs/nix-best-practices.md) is a copy of
the nix.dev best-practices guide, CC-BY-SA-4.0 (see its header).
