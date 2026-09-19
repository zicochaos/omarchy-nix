# Changelog

All notable changes to omarchy-nix, newest first. Dates are UTC.
Upstream adaptation details and the bump checklist:
[`docs/UPSTREAM.md`](docs/UPSTREAM.md).

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
