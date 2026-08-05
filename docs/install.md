# Installing omarchy-nix on a clean NixOS

This is the "new user with a fresh NixOS install" flow: install NixOS
without a desktop using the graphical ISO, wire omarchy-nix in as a
flake input, reboot into the Omarchy desktop. No GUI is preinstalled;
omarchy provides it.

## Prerequisites

- The NixOS **graphical ISO** from <https://nixos.org/download/> — a live
  image: its boot menu lets you pick the live session (GNOME or KDE) and
  the kernel (latest or LTS); neither choice constrains the installed
  system. The included graphical installer (Calamares) does the install.
- A machine (bare metal or VM) with EFI boot and a GPU Hyprland can drive
  (Intel/AMD work; NVIDIA needs the proprietary driver, out of scope here).
- Network access (the install fetches omarchy-nix + nixpkgs from GitHub/cache).

> **Hyprland Cachix is configured automatically.** The omarchy NixOS module
> registers the upstream Hyprland Cachix (`hyprland.cachix.org`) on every
> consumer. The flake Hyprland package is NOT built by Hydra, so without it
> the first install rebuilds Hyprland + mesa + ffmpeg + aquamarine from
> source (a multi-hour build that can OOM a small VM). You don't need to do
> anything; this note is just so you know why the install pulls from a
> non-default cache.

## 1. Install NixOS with the graphical ISO

Boot the ISO and run the installer. The convenient bits:

- **Partitioning** is point-and-click, including full-disk **encryption**
  (a checkbox with a passphrase prompt). If you encrypt, set
  `omarchy.autologin.user` in § 2 for the single-password flow (disk
  unlock at boot, straight into the desktop).
- On the **Desktop** page select **No Desktop** — omarchy provides the
  desktop later; anything else would be replaced anyway.
- The **Allow unfree software** option can stay off: the omarchy module
  whitelists the one unfree default app (obsidian) itself, so a global
  `allowUnfree` is not needed.
- The installer creates your user with a password already set, so you can
  skip the `initialHashedPassword` line in § 2.

Finish the install and reboot into the new system, then continue below.

## 2. Write configuration.nix

This is the user-facing config. Replace the installer's
`/etc/nixos/configuration.nix` with:

```nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    # omarchy-nix provides the whole desktop (Hyprland + quickshell +
    # Plymouth + SDDM theme) when omarchy.enable = true. The flake input
    # is wired in flake.nix (next step).
  ];

  # Bootloader + console.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Flakes, permanently (needed for the flake workflow below).
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Your user. The omarchy Home-Manager module seeds their per-user config
  # (~/.config/hypr, ~/.config/omarchy, theme symlink).
  users.users.alice = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "input" "networkmanager" "ydotool" ];
    # `ydotool` group: voxtype dictation types via ydotoold (group-owned socket)
    # Password for the SDDM prompt (and tty fallback). Skip this if the
    # installer already set a password; otherwise generate YOUR hash on any
    # Linux box and paste it below:
    #   mkpasswd -m yescrypt        # nixpkgs#mkpasswd / whois package
    # The value is world-readable in /nix/store — safe for a hash, not for a
    # plaintext password. Change it with `passwd` after the first login.
    # initialHashedPassword = "$y$j9T$PASTE-YOUR-HASH-HERE";
  };

  # SSH. The omarchy module enables sshd by default (mkDefault) so a
  # `nixos-rebuild switch` that applies omarchy never silently removes the
  # running sshd (an unrecoverable lockout for a remote operator), and forces
  # keys-only logins by default (PasswordAuthentication and
  # KbdInteractiveAuthentication default to false). Add your key to reach
  # the box over SSH:
  users.users.alice.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA... you@your-machine"
  ];
  # Password logins over SSH are off by default; opt in only if you must:
  # services.openssh.settings.PasswordAuthentication = true;

  # omarchy config — the omarchy-nix flake injects omarchy.* as an option
  # once the flake input is wired (flake.nix below). These lines are the
  # only omarchy-specific bit the user writes.
  omarchy.enable = true;
  omarchy.full_name = "Alice Example";
  omarchy.email_address = "alice@example.com";
  omarchy.theme = "ethereal";
  omarchy.scale = 1;            # 1 for 1x displays, 2 for HiDPI
  omarchy.autologin.user = "alice";  # only on LUKS (see options.md); omit for a password prompt

  # Home-Manager for alice. The omarchy HM module itself is shared with all
  # users via home-manager.sharedModules (wired in flake.nix — next step),
  # so this block only carries the per-user settings.
  home-manager.users.alice = {
    home.username = "alice";
    home.homeDirectory = "/home/alice";
    home.stateVersion = "26.05";
    omarchy.enable = true;
  };

  system.stateVersion = "26.05";
}
```

The omarchy NixOS module also whitelists the one unfree default app
(obsidian) via `allowUnfreePredicate`, so you do NOT need
`nixpkgs.config.allowUnfree = true` in your config.

## 3. Wire omarchy-nix as a flake input (recommended)

Create `/etc/nixos/flake.nix`:

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
        ./hardware-configuration.nix
        ./configuration.nix
        omarchy-nix.nixosModules.default       # injects omarchy.* + the flake packages
        home-manager.nixosModules.home-manager
        # Share the omarchy HM module with all home-manager.users so their
        # blocks only carry per-user settings (see configuration.nix).
        { home-manager.sharedModules = [ omarchy-nix.homeManagerModules.default ]; }
      ];
    };
  };
}
```

(For a local checkout instead of GitHub, point `omarchy-nix.url` at
`git+file:///path/to/omarchy-nix`.)

> **Name the configuration after your hostname.** The menu Install/Remove
> actions and `omarchy update` resolve
> `nixosConfigurations."$(hostname)"` — `my-host` above only works if the
> host is actually named `my-host` (see `networking.hostName` in
> `configuration.nix`). If the names differ, the desktop still works but
> the menu commands fail with a resolver error (the full contract is in
> the "Installing apps" section below).

## 4. Apply the config

```bash
# The one-time --option flag enables flakes for THIS run; the config's
# nix.settings line keeps them on afterwards.
sudo nixos-rebuild switch --flake /etc/nixos#my-host \
  --option experimental-features "nix-command flakes"
```

(On a manual minimal-ISO install, `nixos-install --flake /mnt/etc/nixos#my-host
--root /mnt` is the equivalent from the live system.)

Reboot into the desktop.

## 5. First boot

You should land on one of:

- **SDDM password prompt** (omarchy theme), the default when
  `omarchy.autologin.user` is unset. Type your user's password, pick the
  "Hyprland (uwsm)" session, and the omarchy desktop comes up.
- **Direct desktop** (autologin), when `omarchy.autologin.user` is set
  (typical on a LUKS install where you already unlocked the disk at boot).

The bar at the top is quickshell; `Super+Space` opens the Omarchy launcher.

## Recovering if the desktop does not come up

Two options, no reinstall needed:

- **Boot an older generation.** The systemd-boot menu lists every previous
  NixOS generation; pick the one from before you enabled omarchy.
- **Disable omarchy from a tty.** Switch to a virtual console (Ctrl+Alt+F2),
  log in as your user, set `omarchy.enable = false;` in
  `/etc/nixos/configuration.nix`, and test the result:

  ```bash
  sudo nixos-rebuild test --flake /etc/nixos#my-host
  ```

  The omarchy modules are additive, so this reverts to a plain NixOS (no
  desktop) without touching your partitions. Make it permanent with
  `sudo nixos-rebuild switch --flake /etc/nixos#my-host`, or just reboot to
  drop the test activation.

## Installing apps

Super+Space → Install/Remove works the upstream way on NixOS: cataloged
entries (browsers, editors, terminals, gaming, AI, dev toolchains,
services) map to opinionated nixpkgs choices and rebuild the system in
front of you, while Install → Package is a free fzf search over nixpkgs.
Choices land in `omarchy-packages.json` next to your flake. Entries with
no NixOS analogue (AUR, ONCE, NordVPN) are removed from the menu
outright; dev-env entries without a catalog mapping
(laravel/symfony/phoenix) show a declarative note. Selecting Sublime Text
or Bitwarden also permits their insecure dependencies (`openssl-1.1.1w` /
`electron`) on systems that select them; the permission is scoped, not global.

One wiring step is required: point `omarchy.managedPackagesFile` at the JSON
**inside your flake** (flake evaluation is pure; absolute paths outside the
flake are invisible to it):

```nix
omarchy.managedPackagesFile =
  if builtins.pathExists ./omarchy-packages.json
  then ./omarchy-packages.json
  else null;
```

The guard keeps evaluation working before the first menu install; the
add/remove scripts register the JSON with `git add -N` on git-based flakes,
so the flake snapshot picks it up automatically.

All NixOS-specific commands (update, add, remove, presence checks, search)
resolve the consumer flake the same way: `$OMARCHY_NIX_FLAKE` (either a
directory containing `flake.nix` or the path to the `flake.nix` file itself,
which must be named exactly `flake.nix`), then `~/omarchy-nix`,
`~/Projects/omarchy-nix`, `/etc/nixos`. In the fallback order the first
candidate that provides `nixosConfigurations."$(hostname)"` wins. A
candidate is skipped only when its `nixosConfigurations` evaluate cleanly
but have no entry for this host (a bare omarchy-nix library clone). An
evaluation failure keeps the candidate instead of silently skipping it. Set
`OMARCHY_NIX_FLAKE` when your configuration lives elsewhere; an invalid
explicit value fails with diagnostics rather than falling back to
another checkout.
