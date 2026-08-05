# Shared omarchy.* option schema.
#
# Imported by both the NixOS module and the Home-Manager module. Consumers set
# options once at the system level; the HM module mirrors osConfig.omarchy
# into HM config.omarchy so per-user modules can read the same values.
#
# This is deliberately a small surface. Quattro's desktop is driven by the
# vendored upstream tree (Lua config + quickshell shell.json + theme engine),
# so most "configuration" is what upstream already provides. The options here
# are only the things a NixOS consumer needs to set declaratively before the
# first Hyprland session starts.
{ lib, ... }:
{
  omarchyOptions = {
    # Opt-in switch. The module is imported by consumers via the flake's
    # nixosModules.default, but has no effect until `omarchy.enable = true`.
    # This lets `nix flake check` evaluate the module without side effects.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the Omarchy (Quattro) desktop system integration:
        the vendored upstream tree on PATH, the `OMARCHY_PATH` session
        variable, the Quattro runtime dependencies, and a uwsm-managed
        Hyprland session. The Home-Manager module (Stage 4) seeds the
        per-user config on top of this.
      '';
    };

    # The vendored omarchy derivation ($out/share/omarchy). Injected as a
    # `mkDefault` by the flake's nixosModules.default wrapper so consumers
    # don't set it themselves; left null here so the pure module (without the
    # flake wrapper) still evaluates. When null, OMARCHY_PATH is not set and
    # the package is not added to systemPackages.
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The vendored omarchy derivation that installs the upstream tree at
        `$out/share/omarchy`. Set automatically by the flake's
        `nixosModules.default`; leave null to resolve `OMARCHY_PATH` yourself.
      '';
    };

    # Plymouth boot-splash theme package. Injected by the flake wrapper;
    # null here keeps the pure module buildable without the flake.
    plymouthPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The plymouth-omarchy-theme derivation ($out/share/plymouth/themes/
        omarchy). Set automatically by the flake's nixosModules.default when
        omarchy.plymouth.enable is true.
      '';
    };

    # SDDM login theme + Hyprland greeter config package. Injected by the
    # flake wrapper; null here keeps the pure module buildable.
    sddmPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The sddm-omarchy-theme derivation ($out/share/sddm/themes/omarchy +
        hyprland.lua greeter config). Set automatically by the flake's
        nixosModules.default when omarchy.sddm.theme is true.
      '';
    };

    # Upstream-owned packages not available in nixpkgs, built under pkgs/
    # and injected by the flake wrapper (aether, asdcontrol, omacalc,
    # omacut, omawrite, tensaku, try, yaru-theme, hyprland-guiutils,
    # hyprland-preview-share-picker, omarchy-nvim). Added to
    # environment.systemPackages; entries are still subject to
    # omarchy.exclude_packages filtering.
    appPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Upstream-owned Omarchy apps packaged by this flake (not in nixpkgs).
        Set automatically by the flake's nixosModules.default; override to
        trim or extend the set.
      '';
    };

    # The omarchy-nvim starter package (LazyVim + omarchy overlay). The HM
    # module runs its omarchy-nvim-setup script once to seed ~/.config/nvim
    # (mutable seed-and-release, like the other user config stubs).
    nvimPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The omarchy-nvim derivation ($out/share/omarchy-nvim +
        bin/omarchy-nvim-setup). Set automatically by the flake's
        nixosModules.default; null skips nvim config seeding.
      '';
    };

    # Opt-in Fish shell profile. Off by default — Bash stays the
    # Omarchy default shell. Enabling only installs fish + the vendored
    # profile; the login shell remains an explicit per-account setting
    # (users.users.<name>.shell = pkgs.fish) because the module must not
    # guess which account to mutate.
    fish.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install Fish and the vendored Omarchy Fish profile
        (share/fish/vendor_*). Login-shell selection is NOT changed — set
        users.users.<name>.shell = pkgs.fish on the account yourself.
      '';
    };

    # Injected by the flake wrapper (packages.${system}.omarchy-fish).
    fish.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = ''
        The omarchy-fish vendor profile package. Set automatically by the
        flake's nixosModules.default; override to pin a different
        omarchy-fish revision. Must be non-null when omarchy.fish.enable
        is true.
      '';
    };

    # --- Login UX ---
    # Default: SDDM password prompt (safe — the user authenticates at the
    # greeter). On an encrypted (LUKS) install, the user already typed a
    # passphrase to unlock the root disk at boot, so a second SDDM prompt is
    # redundant friction; set omarchy.autologin.user there for the same
    # single-password UX upstream omarchy ships on Arch. This only controls
    # the SDDM autologin toggle — it does NOT configure LUKS itself (that's
    # the user's hardware/bootstrap decision), but it makes the combination
    # sensible when the user did encrypt.
    autologin.user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        Username to auto-login at the SDDM greeter into the Hyprland (uwsm)
        session. null (default) keeps the SDDM password prompt. Set this on
        an encrypted (LUKS) install so the user authenticates once (disk
        unlock) and lands directly on the desktop — mirroring upstream
        omarchy's single-password Arch flow. The user must exist and have a
        password (or be PAM-permitted) for sddm-autologin to succeed.
      '';
    };

    # Fingerprint auth for the lock screen is strictly opt-in: upstream
    # enables it imperatively (omarchy-setup-security-fingerprint writes
    # /etc/pam.d/*) only after the user enrolls a finger. On NixOS the PAM
    # services are declarative, so this option both enables
    # fprintd and ships the omarchy-lock-fingerprint PAM service. Enroll
    # fingers afterwards with `fprintd-enroll`. The password service
    # (omarchy-lock-password) is always present when omarchy is enabled.
    fingerprint.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable fingerprint authentication for the Quickshell lock screen:
        turns on services.fprintd and declares the omarchy-lock-fingerprint
        PAM service (auth required pam_fprintd.so). Off by default — the
        lock screen then authenticates via omarchy-lock-password only.
        Enroll fingerprints per-user with `fprintd-enroll` after rebuild.
      '';
    };

    # strMatching "[^\r\n]*": these values land in environment.d(5)
    # (50-omarchy.conf) and /etc/profile. A raw newline could forge a second
    # env assignment and round-trips badly through systemd's serializer, so
    # CR/LF is rejected at evaluation time.
    full_name = lib.mkOption {
      type = lib.types.strMatching "[^\r\n]*";
      default = "Omarchy User";
      description = "Main user's full name. Used by git and the shell.";
    };

    email_address = lib.mkOption {
      type = lib.types.strMatching "[^\r\n]*";
      default = "omarchy@example.com";
      description = "Main user's email address. Used by git.";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Etc/UTC";
      example = "Europe/Warsaw";
      description = "System timezone (IANA name).";
    };

    # One of the 22 stock Quattro themes shipped under themes/ in the upstream
    # tree (catppuccin, catppuccin-latte, ethereal, everforest, flexoki-light,
    # gruvbox, hackerman, kanagawa, last-horizon, lumon, lupine, matte-black,
    # miasma, nord, osaka-jade, retro-82, ristretto, rose-pine, solitude,
    # tokyo-night, vantablack, white). Left as a free-form string rather than
    # an enum because users can drop their own theme under
    # ~/.config/omarchy/themes/<name>/. The character whitelist
    # still permits every upstream theme name while blocking path traversal
    # ("../") and newline injection — the name is interpolated into filesystem
    # paths and shell commands by the theme engine.
    theme = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "ethereal";
      description = ''
        Default Omarchy theme name (matches a dir in upstream themes/, or a
        user theme under ~/.config/omarchy/themes/). Applied only on first
        activation when ~/.local/state/omarchy/current/theme.name does not
        exist; later changes to this option are no-ops until you edit/remove
        that file or re-run with it removed (then use omarchy-theme-set, or
        let the next activation re-render).
      '';
    };

    # Default terminal resolved through xdg-terminal-exec. Quattro ships foot
    # as the default; ghostty and alacritty/kitty are optional. This option
    # picks which .desktop entry xdg-terminal-exec should resolve to. Same
    # character whitelist as theme: the value is written raw into
    # /etc/xdg/hyprland-xdg-terminals.list (one entry per line), so a newline
    # would forge extra entries.
    terminal = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "foot";
      example = "ghostty";
      description = "Default terminal desktop entry (foot, ghostty, alacritty, kitty).";
    };

    # Hyprland monitor lines. Empty = let Hyprland auto-detect. Each entry is
    # a Hyprland monitor directive string, e.g.
    #   "DP-1, 2560x1440@120, 0x0, 1"
    # Fields: output, mode, position, scale (number or "auto"), transform
    # (0-7); everything after output is optional. Entries are validated and
    # Lua-escaped at evaluation time (modules/lib/omarchy-formats.nix) — a
    # malformed entry fails the build with a clear error instead of writing a
    # monitors.lua that Hyprland cannot parse.
    monitors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Hyprland monitor directives (seeded into ~/.config/hypr/monitors.lua).
        Applied only on first activation when that file does not exist; later
        changes to this option are no-ops until you edit/remove
        ~/.config/hypr/monitors.lua or re-run with the file removed.
      '';
    };

    # Display scale factor for the Hyprland monitor config and the omarchy
    # text-size knob. Quattro's `omarchy display text size` covers 9-20px; this
    # is the coarse integer scale (1 for 1x, 2 for 2x). An enum, not a free
    # int: the monitors.lua template only knows these two scale profiles, so
    # any other value would silently generate a nonsense config.
    scale = lib.mkOption {
      type = lib.types.enum [
        1
        2
      ];
      default = 1;
      description = ''
        Display scale factor (1 for 1x displays, 2 for 2x displays). Used when
        seeding ~/.config/hypr/monitors.lua. Applied only on first activation
        when that file does not exist; later changes to this option are no-ops
        until you edit/remove ~/.config/hypr/monitors.lua or re-run with the
        file removed.
      '';
    };

    # Cross-architecture execution (upstream parity: qemu-user-static-binfmt
    # is installed unconditionally on Arch, so cross-arch docker builds just
    # work). On NixOS this maps to boot.binfmt.emulatedSystems; it is an
    # opt-in list rather than silently enabled: qemu-user joins
    # the system closure and binfmt handlers affect every exec, so the
    # default is empty. Values are NixOS system strings; invalid ones are
    # rejected by boot.binfmt.emulatedSystems' own enum at evaluation time.
    binfmtEmulatedSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "aarch64-linux" ];
      description = ''
        Foreign architectures to execute via qemu-user binfmt registration
        (wired to boot.binfmt.emulatedSystems). Upstream omarchy installs
        qemu-user-static-binfmt unconditionally on Arch; on NixOS emulation
        is opt-in (default []). Example: [ "aarch64-linux" ] to build and run
        ARM64 docker images. Removing entries and rebuilding unregisters the
        handlers (rollback-safe).
      '';
    };

    # Packages to exclude from the default runtime set. Lets a consumer opt
    # out of e.g. obsidian or signal-desktop without forking the module.
    # (List of package *attribute names* as strings, not derivations, so it
    # composes cleanly across the NixOS/HM boundary.)
    exclude_packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "obsidian"
        "signal-desktop"
      ];
      description = "Package attribute names to exclude from the default set.";
    };

    # Path to the menu-managed package list (omarchy-packages.json) written by
    # the Install/Remove menu actions (omarchy-nix-add/remove). The module
    # folds it into environment.systemPackages + feature blocks at eval time,
    # so menu installs are declarative and rollback-safe. Off by default —
    # wire it to the JSON inside your own flake (see the example): pure flake
    # evaluation cannot auto-detect absolute paths like /etc/nixos. Must match
    # where omarchy-nix-add writes (one shared resolver:
    # OMARCHY_NIX_FLAKE as a flake dir or its flake.nix file, fail-closed on
    # an invalid explicit value → ~/omarchy-nix → ~/Projects/omarchy-nix →
    # /etc/nixos, first candidate providing nixosConfigurations."$(hostname)"
    # wins; a candidate is skipped only when its nixosConfigurations
    # evaluate cleanly but lack the host entry (library clones) — eval
    # failures keep the candidate — and writes
    # <flake_dir>/omarchy-packages.json).
    managedPackagesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''
        if builtins.pathExists ./omarchy-packages.json
        then ./omarchy-packages.json
        else null;
      '';
      description = ''
        Path to the menu-managed package list (omarchy-packages.json) folded
        into the system at eval time. null disables menu-managed packages.

        There is no filesystem auto-detection: flake evaluation is pure, so
        builtins.pathExists cannot see absolute paths outside the flake
        (e.g. /etc/nixos/omarchy-packages.json is invisible). Point this at
        the JSON INSIDE your own flake (see the example) — omarchy-nix-add
        writes the file next to your flake.nix and, for git-based flakes,
        registers it with `git add -N` so the flake snapshot includes it.
      '';
    };

    # --- System theme: boot splash + login greeter ---
    # These complete the "Omarchy look" beyond the desktop itself: the boot
    # splash (Plymouth) and the SDDM login greeter (theme + Hyprland greeter
    # config). Both default to enabled so a consumer gets the full Omarchy
    # experience with `omarchy.enable = true`; flip off to keep the host's
    # existing boot/login theme.

    plymouth.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the Omarchy Plymouth boot-splash theme (the splash that runs
        from initrd to display-manager). Sets boot.plymouth.theme to "omarchy"
        and adds the vendored theme package. Disable to keep the host's
        existing boot splash.
      '';
    };

    sddm.theme = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply the Omarchy SDDM login theme and Hyprland greeter config.
        Sets services.displayManager.sddm.theme to "omarchy" and points the
        greeter CompositorCommand at Hyprland with the vendored greeter Lua
        config. Only effective when the omarchy NixOS module's default SDDM
        is enabled (services.displayManager.sddm.enable). Disable to keep the
        host's existing SDDM theme.
      '';
    };
  };
}
