---
name: omarchy
description: >
  Use when customizing an installed omarchy-nix desktop on NixOS, including
  Hyprland, Quickshell, themes, terminals, monitors, keybindings, screenshots,
  reminders, user configuration, package selection, or Omarchy updates.
  Excludes development of the omarchy-nix or upstream Omarchy source trees.
---

# Omarchy on NixOS

Manage end-user customization of the real Omarchy Quattro desktop packaged by
omarchy-nix. Keep Omarchy's runtime UX and commands, but use NixOS-native
package and system management.

Do not use this skill while developing the omarchy-nix or upstream Omarchy
source tree. Read that repository's `AGENTS.md` instead.

## Establish the Runtime

Confirm this is the NixOS port before changing anything:

```bash
test -e /run/current-system
printf 'OMARCHY_PATH=%s\n' "$OMARCHY_PATH"
omarchy version
```

Use `$OMARCHY_PATH` for all packaged Omarchy files. It points into the active
Nix store package and changes across system generations. Never assume a fixed
system path and never modify `$OMARCHY_PATH` or any `/nix/store` path.

Read packaged files freely to understand defaults and command behavior:

```bash
omarchy commands
omarchy theme set --help
sed -n '1,240p' "$(command -v omarchy-theme-set)"
sed -n '1,240p' "$OMARCHY_PATH/default/hypr/windows.lua"
```

## Ownership and Safety

Use the correct ownership layer:

- `$OMARCHY_PATH`: packaged upstream plus NixOS adaptations; read-only.
- `~/.config/`: user-owned, editable runtime configuration.
- `~/.config/omarchy/themes/`: user themes as real directories.
- `~/.config/omarchy/hooks/`: user automation.
- `~/.local/state/omarchy/current/`: generated state; change it through
  Omarchy commands.
- The consumer flake: packages, services, hardware, boot, users, and other
  system configuration.

Back up a user file before a non-trivial edit. Seek confirmation before a
reset command that replaces user configuration. Do not run a system switch,
reboot, shutdown, or destructive reset unless the request authorizes it.

Do not use `pacman`, `yay`, AUR helpers, Arch package names, or Arch repository
instructions. They are not package-management interfaces on NixOS.

Arch system mutators in `$OMARCHY_PATH/bin` are quarantined
(`omarchy-runtime-manifest.nix`): scripts classified `declarative-note` print
the owning NixOS option and exit 0 without changing anything, and menu entries
with no NixOS implementation are hidden. Do not work around a stub by editing
`/etc`, PAM, bootloader, or systemd units imperatively; set the option the
stub names in the consumer flake (`services.resolved`,
`services.openssh.enable`, `omarchy.fingerprint.enable`, `boot.plymouth`,
hardware features) and rebuild. The adapted scripts (`omarchy-setup-security-sshd`,
`omarchy-version`, `omarchy-update-restart`, `omarchy-debug`) keep their
upstream CLI and are safe to run.

## Privilege Escalation

For an interactive script or command run in a visible terminal, use `sudo`
for privileged work; the terminal is the right place to request a password.
On NixOS the setuid wrapper is `/run/wrappers/bin/sudo` (plain `sudo` from
the store is not setuid); Omarchy's own scripts already prefer it.

Use `pkexec` only when the caller cannot interact with a terminal or cannot
enter a password there, such as a command launched by an agent or a
graphical background process; Omarchy shows a graphical authorization
prompt. Do not replace `sudo` with `pkexec` merely because a command
changes system state, and do not wrap commands that already manage their
own elevation (`omarchy update` and `omarchy-nix-add/remove` invoke sudo
themselves for the rebuild).

## System Architecture

Omarchy on NixOS is built on:

| Component | Purpose | Config Location |
|-----------|---------|-----------------|
| **NixOS** | Base OS; system state is declared | the consumer flake (`/etc` is read-only, generated) |
| **Hyprland** | Wayland compositor/WM | `~/.config/hypr/` |
| **Omarchy shell** | Bar, launcher, notifications, OSDs (one Quickshell process) | `~/.config/omarchy/shell.json` |
| **Alacritty/Foot/Kitty/Ghostty** | Terminals | `~/.config/<terminal>/` |
| **Omarchy OSD** | On-screen display | Quickshell plugin |

## Find the Consumer Flake

All NixOS-specific Omarchy commands (update, add, remove, pkg-present, and
the search → add chain) share ONE resolver. Resolution order:

1. `$OMARCHY_NIX_FLAKE`, accepted in two equivalent forms: a directory
   containing `flake.nix`, or the path to the `flake.nix` file itself
   (named exactly `flake.nix`),
2. `~/omarchy-nix`,
3. `~/Projects/omarchy-nix`,
4. `/etc/nixos`.

In the fallback order (2-4) the first candidate that provides
`nixosConfigurations."$(hostname)"` wins. A candidate is skipped only
when its `nixosConfigurations` evaluate cleanly but have no entry for
this host (bare omarchy-nix library clones, e.g. pulled for updates).
An evaluation failure keeps the candidate instead of silently skipping it.

The resolved directory is canonicalized (symlinks, `.`, trailing slashes).
An explicit `OMARCHY_NIX_FLAKE` that is invalid (missing, not a flake
directory, not a `flake.nix` file) fails closed with diagnostics: no
command ever falls back to another checkout, which could otherwise mutate
or rebuild the wrong flake.

Set `OMARCHY_NIX_FLAKE` when the configuration lives elsewhere. Treat the
consumer flake as user/system configuration, not as the omarchy-nix source
repository.

## Command Discovery

Prefer the stable `omarchy <group> <action>` interface:

```bash
omarchy commands
omarchy commands --json
omarchy --help
omarchy theme --help
omarchy refresh --help
omarchy restart --help
```

Common runtime groups:

| Group | Purpose | Example |
| --- | --- | --- |
| `theme` | Theme and background | `omarchy theme set nord` |
| `refresh` | Restore packaged config | `omarchy refresh shell` |
| `restart` | Restart a component | `omarchy restart shell` |
| `toggle` | Toggle a desktop feature | `omarchy toggle nightlight` |
| `bar` | Bar layout and widgets | `omarchy bar --help` |
| `plugin` | User-owned shell plugins | `omarchy plugin --help` |
| `hook` | User automation | `omarchy hook --help` |
| `launch` | Launch apps (user-safe) | `omarchy launch browser` |
| `capture` | Screenshots and recording | `omarchy capture --help` |
| `reminder` | Desktop reminders | `omarchy reminder --help` |
| `install` | Optional software; see the NixOS note below | `omarchy install webapp` |
| `setup` | Setup wizards; mostly declarative stubs on NixOS | `omarchy setup security fingerprint` |
| `update` | Update flake inputs and rebuild | `omarchy update` |

Command discovery lists commands, not applicability: some discovered
commands are `declarative-note` stubs that print the owning NixOS option
and change nothing (see Ownership and Safety), and menu entries with no
NixOS implementation are hidden. Before building a workflow around a
discovered `omarchy install ...` or `omarchy setup ...` command, run it
once and check whether it prints a declarative note instead of acting.
The `pkg` group is not a package-management interface on NixOS (all
`omarchy-pkg-*` are stubs); use the NixOS package commands below.

Use the NixOS-specific package commands instead of `omarchy pkg`:

```bash
omarchy-nix-search
omarchy-nix-add <catalog-id-or-nixpkgs-attribute>
omarchy-nix-remove [catalog-id-or-nixpkgs-attribute]
```

They update `omarchy-packages.json` beside the consumer flake and rebuild.
Use `omarchy-nix-search` for an interactive nixpkgs search. Use a catalog ID
when automating an opinionated menu choice. If the consumer manages packages
directly in Nix, edit its configuration and follow its own validation and
deployment instructions.

Add/remove operations are transactional: a per-file lock serializes them,
the JSON is written atomically, a failed rebuild rolls back only that
operation's own write, and every operation leaves an audit log under
`~/.local/state/omarchy/nix-add/` (or `$XDG_STATE_HOME/omarchy/nix-add/`);
check there first when a menu install disappears with its floating
terminal. Multiple IDs in one call mean one transaction and one rebuild.

`omarchy update` preserves the upstream update UX but uses `nix flake update`
and `nixos-rebuild` internally. Useful controls:

```bash
OMARCHY_NIX_FLAKE=/path/to/config omarchy update
OMARCHY_NIX_REBUILD_CMD=build omarchy update
OMARCHY_NIX_SKIP_FLAKE_UPDATE=1 omarchy update
OMARCHY_NIX_UPDATE_DRY_RUN=1 omarchy update
```

Review a dry run or `build` before a risky deployment. The full
update wrapper can still run Omarchy migrations and hooks; a dry-run variable
only suppresses the Nix update/rebuild core.

## User Configuration

### Hyprland

User overrides live in:

```text
~/.config/hypr/
├── hyprland.lua
├── bindings.lua
├── monitors.lua
├── input.lua
├── looknfeel.lua
├── autostart.lua
└── hyprsunset.conf
```

After any change, validate:

```bash
hyprctl reload
hyprctl configerrors
```

Resolve every reported error before declaring success.

Before rebinding a key, inspect current bindings with
`omarchy menu keybindings --print`. If the key already exists, call
`hl.unbind(...)` before the new `o.bind(...)` and tell the user what it
previously did.

Window-rule syntax changes frequently. Check the documentation for the
installed Hyprland version before writing rules. Prefer Omarchy's
`o.window(match, rules)` helper and inspect examples in
`$OMARCHY_PATH/default/hypr/windows.lua`.

### Omarchy Shell

The bar, launcher, notifications, OSDs, and panels share one Quickshell
process.

```text
~/.config/omarchy/shell.json
~/.config/omarchy/plugins/<plugin-id>/
$OMARCHY_PATH/config/omarchy/shell.json
```

The shell config hot-reloads. Clone a built-in plugin before modifying it:

```bash
omarchy plugin clone omarchy.workspaces
# Edit ~/.config/omarchy/plugins/local.workspaces/; saved changes reload automatically.
```

Never edit `$OMARCHY_PATH/shell/plugins/`.

### Themes

Create custom themes under `~/.config/omarchy/themes/<name>/`. Copy a stock
theme from `$OMARCHY_PATH/themes/<name>/` as a starting point, then apply it:

```bash
omarchy theme list
omarchy theme current
omarchy theme set <name>
omarchy theme bg next
omarchy theme install <git-url>   # installs into ~/.config/omarchy/themes
```

Do not modify a stock theme in the Nix store.

### Terminals

User terminal configs live at:

```text
~/.config/alacritty/alacritty.toml
~/.config/foot/foot.ini
~/.config/kitty/kitty.conf
~/.config/ghostty/config
```

Run `omarchy restart terminal` after changing the active terminal config.

### Other Configs

| App | Location |
| --- | --- |
| btop | `~/.config/btop/btop.conf` |
| fastfetch | `~/.config/fastfetch/config.jsonc` (no system default is installed on NixOS; the user file is the only config) |
| lazygit | `~/.config/lazygit/config.yml` |
| starship | `~/.config/starship.toml` |
| git | `~/.config/git/config` (user name/email are written by first-run from `omarchy.full_name` / `omarchy.email_address`; change them in the consumer flake, not by hand) |

### Hooks

Install independent scripts under an event's `.d` directory with:

```bash
omarchy hook install <event> <script>
```

Common events include `battery-low`, `font-set`, `post-boot`, `post-update`,
and `theme-set`. The inherited `pre-refresh-pacman` hook is Arch-specific and
does not run the NixOS update core.

## Common Workflows

For a keybinding:

1. Inspect current bindings.
2. Back up `~/.config/hypr/bindings.lua`.
3. Unbind an existing chord if necessary.
4. Add the Lua binding.
5. Reload and check `hyprctl configerrors`.

For monitors:

1. Run `hyprctl monitors all`.
2. Edit `~/.config/hypr/monitors.lua` using `hl.monitor({ ... })`.
3. Reload and verify every active output.

For fonts:

```bash
omarchy font list               # Available fonts
omarchy font current            # Current font
omarchy font set <name>         # Change font (fires the font-set hook)
```

For system power/session actions (user-safe wrappers around
loginctl/systemctl; they do not edit any declarative config):

```bash
omarchy system lock             # Lock screen
omarchy system shutdown         # Shutdown
omarchy system reboot           # Reboot
```

Do not run shutdown/reboot from an agent session unless the request
explicitly authorizes it (see Ownership and Safety).

For a package:

1. Prefer `omarchy-nix-search` for an interactive request.
2. Use `omarchy-nix-add` only with a verified catalog ID or nixpkgs
   attribute.
3. Verify the rebuild and the resulting command or desktop entry.
4. Use `omarchy-nix-remove` for items managed through
   `omarchy-packages.json`.

For a reset, request confirmation first, then use the narrowest command:

```bash
omarchy refresh config hypr/bindings.lua
omarchy refresh shell
omarchy refresh hyprland
```

For troubleshooting:

```bash
omarchy debug --no-sudo --print
omarchy commands
hyprctl configerrors
systemctl --user --failed
```

Always use `--no-sudo --print` with `omarchy debug` in an agent session.

`omarchy reinstall` (upstream's nuclear config-reset option) only chains two
steps that are both stubs on NixOS (`reinstall-pkgs` and the declarative-note
`reinstall-configs`) and then offers a reboot; it resets nothing. To re-seed
a user config, delete the file
under `~/.config/` and rebuild (`home-manager switch` or
`nixos-rebuild switch`); the seed-if-absent activation copies the packaged
default again. To restore one file without a rebuild, use
`omarchy refresh config <path-relative-to-~/.config>` (creates a timestamped
backup first).

For reminders:

```bash
omarchy reminder 15 "Pickup Jack"
omarchy reminder show
omarchy reminder clear
```

## Decision Framework

1. If it is a stock runtime action, use the documented `omarchy` command.
2. If it is user customization, edit `~/.config` or a user theme/plugin/hook.
3. If it installs or removes software, use the NixOS package workflow.
4. If it changes services, users, boot, hardware, or policy, change the
   consumer flake and follow its deployment rules.
5. If it changes packaged Omarchy or omarchy-nix itself, stop using this skill
   and follow the source repository instructions.

Verify observable behavior after every change; a successful command alone is
not proof that the desktop behavior is correct.

## Out of Scope

This skill intentionally does not cover source development. Do not use it
for:

- Editing anything under `$OMARCHY_PATH` or any other `/nix/store` path
  (impossible anyway, since the store is read-only; the change belongs in the
  omarchy-nix repository).
- Developing omarchy-nix or upstream Omarchy: migrations, packaging, the
  NixOS/Home-Manager modules, or upstream's `omarchy dev ...` workflows.
  Follow the repository's `AGENTS.md` instead.
- Arch package management: `pacman`, `yay`, AUR helpers, Arch package
  names. There is no AUR on NixOS.

## Example Requests

- "Change my theme to catppuccin" → `omarchy theme set catppuccin`
- "Add a keybinding for Super+E to open the file manager" → check existing
  bindings first, `hl.unbind` if needed, then `o.bind` in
  `~/.config/hypr/bindings.lua`
- "Configure my external monitor" → edit `~/.config/hypr/monitors.lua`,
  then `hyprctl reload` + `hyprctl configerrors`
- "Make the window gaps smaller" → edit `~/.config/hypr/looknfeel.lua`
- "Set up night light at sunset" → `omarchy toggle nightlight` or edit
  `~/.config/hypr/hyprsunset.conf`
- "Change the UI font" → `omarchy font list`, then `omarchy font set <name>`
- "Install Firefox" → `omarchy-nix-add install.browser.firefox` (or
  `omarchy-nix-search` interactively), never `omarchy pkg add`
- "Install a dev database" → no catalog entry exists for databases/docker:
  enable them in the consumer flake (e.g. `virtualisation.docker.enable =
  true;`) and rebuild; a direct `omarchy install ...` may be a
  declarative-note stub
- "Set a reminder to pick up Jack in 15 minutes" →
  `omarchy reminder 15 "Pickup Jack"`
- "Run a script every time I change themes" →
  `omarchy hook install theme-set <script>`
- "Change how workspace labels are rendered" →
  `omarchy plugin clone omarchy.workspaces`, then edit the clone (saved
  changes reload automatically)
- "Lock after ten minutes" → set `idle.lock` to `600` in
  `~/.config/omarchy/shell.json`
- "Reset the shell/bar to defaults" → ask for confirmation, then
  `omarchy refresh shell`
- "Enable fingerprint unlock" → set `omarchy.fingerprint.enable = true` in
  the consumer flake and rebuild; the `omarchy setup security fingerprint`
  wizard is a stub on NixOS
