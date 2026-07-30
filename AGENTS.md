# omarchy-nix Agent Guide

A NixOS port of [basecamp/omarchy](https://github.com/basecamp/omarchy) (the
Quattro generation, [upstream PR #6231](https://github.com/basecamp/omarchy/pull/6231)).

> **START HERE:** read [`README.md`](README.md) and the docs in
> [`docs/`](docs/) before any work. Process-level checks (`ps aux`,
> `nix flake check`) are necessary but **not sufficient**: "verified" means
> behaviorally verified in a running desktop session.

## Hard rules

- **This project is vendored, not rewritten.** The upstream `basecamp/omarchy`
  tree (the `quattro` branch) is packaged as a Nix derivation; we do not
  hand-translate bash scripts, QML, or Lua into Nix. Updating to a newer
  Omarchy release means `nix flake lock --update-input omarchy-src` + rebuild,
  not editing modules.

## Architecture (one paragraph)

Upstream Quattro's "desktop" is a **single `quickshell` process** that provides
the bar, launcher, menus, notifications, OSDs, control panels, lock screen,
and polkit agent as plugins, plus a **Lua-based Hyprland config** (≥0.56),
~383 `omarchy-*` bash scripts in `bin/`, and a **TOML + template theme
engine**. Waybar/wofi/mako/hyprlock/hyprpaper/swaybg/polkit-gnome are gone
in Quattro. This port packages the upstream tree at `$out/share/omarchy`,
exports `OMARCHY_PATH`, and seeds `~/.config/hypr/hyprland.lua` so Hyprland's
autostart launches `quickshell -p $OMARCHY_PATH/shell`.

## Project layout

```
flake.nix              # inputs + outputs (packages, modules, checks, configs)
config.nix             # public omarchy.* option schema
pkgs/                  # derivations:
  omarchy.nix          #   vendoring: omarchy-src -> $out/share/omarchy
  omarchy-catalog.nix  #   Install/Remove menu catalog (nix-catalog.json)
  omarchy-migrations.nix  # migration classification manifest
  migrations-nix/      #   NixOS adapter scripts for class "adapter"
  plymouth-omarchy-theme.nix  #   boot-splash theme
  sddm-omarchy-theme.nix      #   login theme + Hyprland greeter config
modules/nixos/         # NixOS module: env, runtime deps, Hyprland, themes
modules/home-manager/  # HM module: per-user config seed (hypr entry + stubs)
tests/desktop.nix      # automated desktop test (checks.omarchy-desktop)
tests/ux.nix           # behavioral acceptance (checks.omarchy-ux)
example/               # demo consumer configuration.nix
docs/                  # install.md, options.md, UPSTREAM.md, vm.md, nix-best-practices.md
```

## Inputs

- `nixpkgs` → `nixos-26.05` (stable, so consumers on a stable NixOS install
  do NOT get shifted to unstable by `nixos-rebuild switch --flake`).
- `omarchy-src` → `github:basecamp/omarchy/quattro`, `flake = false` (it is not
  a flake; we vendor it).
- `hyprland` → `github:hyprwm/Hyprland` (needs ≥0.56 for Lua config).
- `home-manager` → `github:nix-community/home-manager`, follows `nixpkgs`.
- `quickshell`: `pkgs.quickshell` (nixpkgs, v0.3.0). Sufficient for the
  current upstream `shell.qml`; `checks.omarchy-desktop` verifies the shell
  loads and registers its instance. If a future upstream rev requires a newer
  API, add an explicit `github:quickshell-mirror/quickshell` input and use
  its `#quickshell` output.

## Verification (every stage)

1. `nix flake check` must pass before any commit. This includes
   `checks.omarchy-desktop`, an automated NixOS test that boots a VM with
   `virtio-gpu-pci` and asserts the full desktop stack comes up (Hyprland +
   quickshell), and `checks.omarchy-ux`, behavioral acceptance (Super+Enter
   opens foot, theme switching, config editability, binary coverage of every
   menu/autostart/systemd command). Do not commit red.
2. `nix build .#omarchy`; verify
   `result/share/omarchy/{bin,shell,default,themes}`.
3. For manual desktop exploration, build the demo VM and run with
   `QEMU_OPTS="-device virtio-gpu-pci" ./result-vm/bin/run-nixos-vm`; see
   [`docs/vm.md`](docs/vm.md).

## Out of scope (do not do unless explicitly asked)

- Configuring LUKS itself (partitioning, `boot.initrd.luks` devices) is
  the user's bootstrap decision in their own `hardware-configuration.nix`.
  The omarchy module only makes the *combination* sensible: if the user did
  encrypt, `omarchy.autologin.user` gives the single-password UX (disk
  unlock at boot, land directly on the desktop, mirroring upstream omarchy).
- Translating upstream bash/QML/Lua into Nix. Vendor, don't rewrite.

## Code conventions

- Format with `nixfmt-tree` (the `formatter` output).
- 2-space indent in Nix.
- Options live under `omarchy.*`, `camelCase` keys.
- Follow the Nix code conventions in
  [`docs/nix-best-practices.md`](docs/nix-best-practices.md): quote URLs, prefer
  `let ... in` over `rec`, avoid top-level `with` and `<...>` lookup paths,
  pass explicit `config`/`overlays` when importing nixpkgs, use
  `lib.recursiveUpdate` for nested merges, and `builtins.path { path, name }`
  for reproducible source paths. (That file is a verbatim copy of the nix.dev
  best-practices guide, CC-BY-SA-4.0; see its header.)

## Updating upstream

```bash
nix flake lock --update-input omarchy-src
nix flake check
```

Commit `flake.lock` together with any adaptation fixes the new upstream rev
requires (renamed files, new bin scripts, new theme templates). One revision,
one commit.

---

Maintainer-internal operational docs (release process, test fleet, decision
records) live on the private dev remote and are intentionally not part of
this repository.
