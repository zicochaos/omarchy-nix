# Changelog

All notable changes to omarchy-nix, newest first. Dates are UTC.
Upstream adaptation details and the bump checklist:
[`docs/UPSTREAM.md`](docs/UPSTREAM.md).

## 2026-09-14

- Install → Development → Rust now yields the whole toolchain, not just
  the compiler: `rustfmt` and `clippy` join `rustc` and `cargo` in the
  catalog entry (#115, PR #116). Arch ships one `rust` package with
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
