# Machine-readable classification of upstream runtime commands that
# touch NixOS-owned system state, and of the menu entries that reach them.
#
# Two-tier scheme, enforced by checks.omarchy-runtime
# (tests/checks/omarchy-runtime.nix):
#
#   1. Every scanned file NOT listed here is verified user-safe by
#      construction: the build-time scan finds no forbidden mutation pattern
#      (pacman/ufw/systemctl enable//etc-writes/modprobe/... and, as the
#      catch-all, any sudo/pkexec invocation) in its body. Scanned: every
#      regular file in bin/ (whatever its mode), install/user/** (first-run
#      and finalize-user), default/bash/fns/*, the user-safe vendored
#      migrations and the NixOS migration adapters. A NEW upstream file that
#      mutates system state matches a pattern, is missing from this
#      manifest, and FAILS the check — classification is forced at bump
#      time. This is the fail-closed half of the scheme.
#
#   2. Every entry listed here carries an explicit class (bin scripts by
#      name under `scripts`, other files by path under `files`):
#      - declarative-note: body fully replaced with a pointer to the NixOS
#        option that owns the state (exit 0). Verified by output: the stub
#        prints exactly its `note`.
#      - nixos-adapted: hand-rewritten or patched for NixOS (system
#        mutations removed, user-state flows kept).
#      - user-safe: kept verbatim.
#      - port-owned: written by this port (not in the upstream tree).
#      For the last three the scan allows ONLY the declared `allow` pattern
#      groups (each entry documents why the leftover is safe), and every
#      declared group must still match (a stale allow fails too).
#
# Keys are checked against the UPSTREAM tree (port-owned: against the
# packaged bin/, and must not exist upstream). `note` is the pointer text
# baked into generated declarative-note stubs by pkgs/omarchy.nix.
# hiddenMenuIds are deleted from omarchy-menu.jsonc at package time (the
# scripts behind them are stubbed, so a stale caller can never reach a real
# Arch mutation).
{
  scripts = {
    # --- declarative-note: stubbed; menu entry hidden where one existed ----
    omarchy-dns = {
      class = "declarative-note";
      note = "DNS is declarative: set services.resolved / networking.nameservers in your flake config and rebuild.";
    };
    omarchy-hibernation-setup = {
      class = "declarative-note";
      note = "Hibernation is declarative: configure boot.resumeDevice + swapDevices in your hardware-configuration.nix.";
    };
    omarchy-hibernation-remove = {
      class = "declarative-note";
      note = "Hibernation is declarative: remove boot.resumeDevice + swapDevices from your hardware-configuration.nix.";
    };
    omarchy-setup-security-fido2 = {
      class = "declarative-note";
      note = "Security-key (U2F) auth is declarative: configure security.pam.u2f in your flake config.";
    };
    omarchy-remove-security-fido2 = {
      class = "declarative-note";
      note = "Security-key (U2F) auth is declarative: adjust security.pam.u2f in your flake config.";
    };
    omarchy-sudo-passwordless = {
      class = "declarative-note";
      note = "Sudo policy is declarative: set security.sudo.wheelNeedsPassword = false (or security.sudo.extraRules) in your flake config.";
    };
    omarchy-setup-direct-boot = {
      class = "declarative-note";
      note = "Boot entries are declarative: configure boot.loader.* (systemd-boot / EFISTUB) in your flake config.";
    };
    omarchy-toggle-hybrid-gpu = {
      class = "declarative-note";
      note = "GPU switching is declarative: configure PRIME / supergfxd in your flake config (see nixos-hardware).";
    };
    omarchy-install-gaming-xbox-controllers = {
      class = "declarative-note";
      note = "Xbox controllers: use Menu -> Install -> Gaming -> Xbox Controllers, or set hardware.xpadneo.enable = true in your flake config.";
    };
    # 2026-09-15: seeds the Claude extension's external-update JSON into
    # /usr/share/{chromium,google-chrome,microsoft-edge}/extensions —
    # /usr/share does not exist on NixOS and browser extension policy is
    # module-owned. Called best-effort (2>/dev/null || true) by
    # omarchy-default-agent after picking Claude, so the stub's note is only
    # visible on direct invocation.
    omarchy-install-chromium-claude = {
      class = "declarative-note";
      note = "The Claude browser extension is declarative: add id fcoeoabgfenejglbffodgkkbkcdhcgfn to programs.chromium.extensions (or your browser's extension option) in your flake config.";
    };
    omarchy-remove-gaming-xbox-controllers = {
      class = "declarative-note";
      note = "Xbox controllers: use Menu -> Remove -> Gaming -> Xbox Controllers, or set hardware.xpadneo.enable = false in your flake config.";
    };
    omarchy-refresh-plymouth = {
      class = "declarative-note";
      note = "Boot splash is declarative: omarchy.plymouth.enable / boot.plymouth is applied at rebuild time.";
    };
    omarchy-plymouth-set = {
      class = "declarative-note";
      note = "Boot splash is declarative: omarchy.plymouth.enable / boot.plymouth is applied at rebuild time.";
    };
    omarchy-plymouth-set-by-theme = {
      class = "declarative-note";
      note = "Boot splash is declarative: omarchy.plymouth.enable / boot.plymouth is applied at rebuild time.";
    };
    omarchy-plymouth-reset = {
      class = "declarative-note";
      note = "Boot splash is declarative: omarchy.plymouth.enable / boot.plymouth is applied at rebuild time.";
    };
    omarchy-menu-timezone = {
      class = "declarative-note";
      note = "Timezone is declarative: set omarchy.timezone / time.timezone in your flake config and rebuild.";
    };
    omarchy-install-service-sunshine = {
      class = "declarative-note";
      note = "Sunshine is declarative: set services.sunshine.enable = true in your flake config (the module opens its firewall ports).";
    };
    omarchy-remove-service-sunshine = {
      class = "declarative-note";
      note = "Sunshine is declarative: set services.sunshine.enable = false in your flake config and rebuild.";
    };
    # 8b4eae6 SSH Agent service: upstream enables/disables gcr-ssh-agent.socket
    # per user. NixOS enables it system-wide (services.gnome.gcr-ssh-agent,
    # default follows gnome-keyring, which the module turns on), and a user
    # `systemctl --user disable` cannot undo a unit enabled from /etc.
    omarchy-setup-security-ssh-agent = {
      class = "declarative-note";
      note = "The SSH agent is declarative: services.gnome.gcr-ssh-agent.enable (on by default with omarchy's gnome-keyring) already runs gcr-ssh-agent and exports SSH_AUTH_SOCK.";
    };
    omarchy-remove-service-ssh-agent = {
      class = "declarative-note";
      note = "The SSH agent is declarative: set services.gnome.gcr-ssh-agent.enable = false in your flake config and rebuild.";
    };
    omarchy-remove-service-tailscale = {
      class = "declarative-note";
      note = "Use Menu -> Remove -> Service -> Tailscale (omarchy-nix-remove), or services.tailscale.enable = false in your flake config.";
    };
    omarchy-dev-link = {
      class = "declarative-note";
      note = "Dev checkouts: point the omarchy-nix input at a local checkout (url = path:/your/checkout) in the consumer flake and rebuild.";
    };
    omarchy-dev-unlink = {
      class = "declarative-note";
      note = "Dev checkouts: point the omarchy-nix input back at the repository in the consumer flake and rebuild.";
    };
    omarchy-dev-pkg-test = {
      class = "declarative-note";
      note = "Arch PKGBUILD builds (makepkg) are not applicable on NixOS.";
    };
    omarchy-install-browser = {
      class = "declarative-note";
      note = "Browsers come from the nixpkgs catalog (Menu -> Install -> Browser). zen / brave-origin are AUR-only and not packaged in nixpkgs.";
    };
    omarchy-remove-browser = {
      class = "declarative-note";
      note = "Browsers are removed via Menu -> Remove -> Browser (omarchy-nix-remove); browser policy files under /etc are declarative on NixOS.";
    };
    omarchy-refresh-limine = {
      class = "declarative-note";
      note = "The bootloader is declarative: configure boot.loader.* in your flake config; NixOS does not use limine tooling.";
    };
    omarchy-reinstall-configs = {
      class = "declarative-note";
      note = "User configs are seeded by Home Manager: remove the file under ~/.config and rebuild (home-manager switch) to re-seed it.";
    };
    omarchy-refresh-sddm = {
      class = "declarative-note";
      note = "The SDDM theme is declarative: omarchy.sddm.theme = true points services.displayManager.sddm.theme at the packaged theme (pkgs/sddm-omarchy-theme.nix).";
    };
    omarchy-dev-install-ydoo = {
      class = "declarative-note";
      note = "Input-emulation daemons are declarative: programs.ydotool.enable = true in your flake config.";
    };
    # v4.0.0 renames + new ISO/factory-reset surface (renamed from
    # omarchy-setup-* / introduced by the deferred-provisioning work):
    omarchy-apply-system = {
      class = "declarative-note";
      note = "System setup is the NixOS module: omarchy.enable = true declares the packages, services and /etc equivalents the ISO installer writes by hand.";
    };
    omarchy-apply-hardware = {
      class = "declarative-note";
      note = "Hardware setup is declarative: import a nixos-hardware NixOSModule or set hardware.* options in your flake config (the module already declares the defaults the ISO writes).";
    };
    omarchy-provision-owner = {
      class = "declarative-note";
      note = "Deferred first-boot provisioning is ISO-installer machinery (LUKS re-key, user creation, /etc writes); on NixOS users are declared with users.users.<name> in the flake.";
    };
    omarchy-system-factory-reset = {
      class = "declarative-note";
      note = "Factory reset is btrfs/@factory + limine ISO machinery with no NixOS analogue; roll back with nixos-rebuild switch --rollback or a boot-menu generation.";
    };
    omarchy-system-factory-reset-finish = {
      class = "declarative-note";
      note = "Factory reset is btrfs/@factory + limine ISO machinery with no NixOS analogue; roll back with nixos-rebuild switch --rollback or a boot-menu generation.";
    };
    omarchy-update-pkg-prune = {
      class = "declarative-note";
      # Never recommend `nix-collect-garbage -d` here: it deletes every old
      # generation, i.e. every rollback, which is the opposite of upstream's
      # keep-two-versions cache policy.
      note = "No pacman package cache to prune; old system generations are your rollbacks. To reclaim space while keeping recent ones, enable nix.gc.automatic with nix.gc.options set to --delete-older-than 14d in your flake, or run sudo nix-collect-garbage --delete-older-than 14d.";
    };
    # v4.0.2 sudoless Docker toggle: `usermod -aG docker` / `gpasswd -d` are
    # account mutations; on NixOS group membership is part of the flake.
    omarchy-setup-security-sudoless-docker = {
      class = "declarative-note";
      note = "Group membership is declarative: add \"docker\" to users.users.<name>.extraGroups in your flake config and rebuild (then log out/in — the docker group is passwordless root, the same warning upstream shows).";
    };
    omarchy-remove-security-sudoless-docker = {
      class = "declarative-note";
      note = "Group membership is declarative: remove \"docker\" from users.users.<name>.extraGroups in your flake config and rebuild.";
    };
    # Lutris comes from the catalog (the menu routes to omarchy-nix-add);
    # upstream's script ends with `sudo sed -i … /usr/bin/lutris` to pin
    # the system Python, a path that does not exist on NixOS (the command
    # failed there after asking for the password). Reached only directly.
    omarchy-install-gaming-lutris = {
      class = "declarative-note";
      note = "Lutris comes from the nixpkgs catalog: use Menu -> Install -> Gaming -> Lutris (omarchy-nix-add install.gaming.lutris); the nixpkgs build already runs on its own Python.";
    };
    # `sudo rm -f /usr/share/chromium/extensions/<id>.json` (absent on NixOS:
    # a password prompt for a no-op) + the pkg-drop stub, which leaves the
    # catalog package installed. Reached only directly (`omarchy remove
    # service 1password`); the catalog removal is the real path.
    omarchy-remove-service-1password = {
      class = "declarative-note";
      note = "1Password is removed with omarchy-nix-remove install.service.1password (or from your flake config); there is no /usr/share browser extension file to delete on NixOS.";
    };

    # --- nixos-adapted: hand-rewritten in pkgs/omarchy.nix postPatch --------
    # (system mutations removed; user-state flows kept; `allow` lists the
    # audited privileged leftovers)
    omarchy-setup-security-sshd = {
      class = "nixos-adapted";
    };
    omarchy-remove-security-sshd = {
      class = "nixos-adapted";
    };
    omarchy-remove-dev-env = {
      class = "nixos-adapted";
      # upstream's command-scoped sudo probes (sudo -k / -N -V) and the
      # `sudo -N rm -f /usr/local/bin/opam` cleanup, pointed at the setuid
      # wrapper; nothing NixOS-owned is touched (/usr/local is not).
      allow = [ "sudo" ];
    };
    omarchy-remove-launcher-entry = {
      class = "nixos-adapted";
    };
    omarchy-version = {
      class = "nixos-adapted";
    };
    omarchy-update-restart = {
      class = "nixos-adapted";
    };
    omarchy-debug = {
      class = "nixos-adapted";
      # read-only `sudo dmesg` for the report.
      allow = [ "sudo" ];
    };
    omarchy-upload-log = {
      class = "nixos-adapted";
      # prose only: the "install log not found (looked at /var/log ...)"
      # warning; the log paths are read, never written.
      allow = [ "var-write" ];
    };
    omarchy-theme-set-browser = {
      class = "nixos-adapted";
    };
    # v4.0.1: the browser-accent policy helper — its only caller
    # (omarchy-theme-set-browser) is a no-op on NixOS, so pkgs/omarchy.nix
    # replaces it with the same silent no-op (it was classified
    # declarative-note, but that generated stub was overwritten by the
    # silent one and its note never shipped).
    omarchy-theme-set-browser-policy = {
      class = "nixos-adapted";
    };
    omarchy-update-firmware = {
      class = "nixos-adapted";
      # `sudo fwupdmgr update`: firmware updates run through the declarative
      # services.fwupd daemon; the ESP staging copy is removed.
      allow = [ "sudo" ];
    };
    # omarchy-install-ai-chatgpt: the pkg-add core already routes into the
    # declarative stub; only the /usr/bin/chatgpt launch path is adapted
    # (binaries live on PATH on NixOS).
    omarchy-install-ai-chatgpt = {
      class = "nixos-adapted";
    };
    # v4.0.2 remove-ai wave: only the ollama variant mutates system state
    # (unit + /var/lib) — both are services.ollama-owned on NixOS; the
    # pkg-drop core routes into the declarative flow and the $HOME model
    # cleanup is kept.
    omarchy-remove-ai-ollama = {
      class = "nixos-adapted";
    };
    omarchy-install-dev-env = {
      class = "nixos-adapted";
    };
    # Replaced or patched by the NixOS update/migration flow; the sudo
    # leftovers are the update's own authorization:
    # - the command-scoped sudo boundary of omarchy-update (349ecc0): `sudo
    #   true` authorization + keepalive, sudo -k revocation, the sleep
    #   inhibitor's sudo/pkexec hold — paths pointed at the setuid wrappers.
    omarchy-update = {
      class = "nixos-adapted";
      allow = [ "sudo" ];
    };
    omarchy-security-functions = {
      class = "nixos-adapted";
      allow = [ "sudo" ];
    };
    omarchy-update-stay-awake = {
      class = "nixos-adapted";
      allow = [ "sudo" ];
    };
    # - the NixOS-native package refresh: sudo nix flake update (root-owned
    #   flake) + sudo nixos-rebuild.
    omarchy-update-system-pkgs = {
      class = "nixos-adapted";
      allow = [ "sudo" ];
    };
    # - prose only: "skipping snapper snapshot" / "sudo nixos-rebuild
    #   list-generations" hints; nothing is run.
    omarchy-snapshot = {
      class = "nixos-adapted";
      allow = [
        "snapper"
        "sudo"
      ];
    };

    # --- port-owned: written by pkgs/omarchy.nix installPhase -------------
    # Menu Install/Remove transactions: sudo only for a root-owned consumer
    # flake (read/write of omarchy-packages.json and the options pair,
    # intent-to-add in a repository the user does not own) and the
    # nixos-rebuild itself.
    omarchy-nix-add = {
      class = "port-owned";
      allow = [ "sudo" ];
    };
    omarchy-nix-remove = {
      class = "port-owned";
      allow = [ "sudo" ];
    };
    omarchy-nix-pkglib = {
      class = "port-owned";
      allow = [ "sudo" ];
    };
    # prose only: "Arch Omarchy installs packages with pacman/yay".
    omarchy-nix-declarative-note = {
      class = "port-owned";
      allow = [ "pkg-helpers" ];
    };

    # --- user-safe: kept verbatim; `allow` lists the audited leftovers ------
    # v4.0.3 AI wave. The Hermes DESKTOP pair is unreachable on NixOS
    # (hermes-desktop is not on the pin and no in-repo package exists — those
    # menu entries are dropped); the Hermes AGENT is available separately
    # through the `hermes-agent` flake input and the injected
    # install.ai.hermes catalog entry. Both scripts kept verbatim with their
    # user-scope leftovers declared. OpenClaw IS installable here (catalog
    # entry install.ai.openclaw): systemctl --user disable --now of the
    # per-user openclaw-gateway unit, plus $HOME config cleanup — user scope
    # only, package removal routes into omarchy-pkg-drop.
    omarchy-install-ai-hermes = {
      class = "user-safe";
      # 349ecc0 slimmed it to `omarchy-install-hermes-cli --now` + the
      # desktop launch; the gateway-unit handling moved into
      # install-hermes-cli, so nothing is left to allow.
    };
    omarchy-install-hermes-cli = {
      class = "user-safe";
      # 349ecc0: systemctl --user stop of the per-user omarchy-hermes-theme
      # unit (|| true); its hermes-desktop pkg-add routes into the
      # declarative stub. Reached by migration 1790017600 (skipped here) and
      # install-ai-hermes, not by the port's menu.
      allow = [ "systemctl-user" ];
    };
    omarchy-remove-ai-hermes = {
      class = "user-safe";
      # systemctl --user disable/stop of the per-user hermes gateway units and
      # the omarchy-hermes-theme unit.
      allow = [ "systemctl-user" ];
    };
    omarchy-remove-ai-openclaw = {
      class = "user-safe";
      # systemctl --user disable --now of the per-user openclaw-gateway
      # unit + daemon-reload/reset-failed (all --user scope).
      allow = [ "systemctl-user" ];
    };
    omarchy-audio-tuning = {
      class = "user-safe";
      # systemctl --user manages ONLY the per-user omarchy-speaker-tuning
      # unit + files under ~/.config — user scope, no /etc, no sudo.
      allow = [ "systemctl-user" ];
    };
    omarchy-voxtype-remove = {
      class = "user-safe";
      # systemctl --user disable of the per-user voxtype daemon (user scope);
      # package removal routes into the omarchy-pkg-drop stub.
      allow = [ "systemctl-user" ];
    };
    omarchy-restart-trackpad = {
      class = "user-safe";
      # sudo modprobe -r + modprobe of intel_quicki2c and a sudo tee of the
      # i2c_hid_acpi unbind/bind sysfs files: transient kernel/device state,
      # an upstream-designed hardware reset; no persistent config is touched.
      allow = [
        "modprobe"
        "sudo"
      ];
    };
    omarchy-windows-vm = {
      class = "user-safe";
      # modprobe + "sudo systemctl start docker" strings are printed hints in
      # an error dialog, never executed. Its privileged actions re-exec
      # /usr/bin/omarchy-windows-vm through pkexec, a path that does not
      # exist on NixOS: priv_target fails closed ("refusing to run a
      # non-root-owned command as root"), so only the docker-group path runs.
      allow = [
        "modprobe"
        "sudo"
        "systemctl-restart"
      ];
    };
    omarchy-hibernation-available = {
      class = "user-safe";
      # Read-only probes: swap size + /etc/mkinitcpio.conf.d/omarchy_resume.conf
      # existence. On NixOS the probe reports "unavailable", which correctly
      # hides the Hibernate menu entry. Nothing is written; initrd-boot hits
      # only on the matched mkinitcpio path.
      allow = [
        "etc-sysconf"
        "initrd-boot"
      ];
    };
    omarchy-dev-status = {
      class = "user-safe";
      # Read-only check of /etc/omarchy.conf (always absent on NixOS) and
      # read-only sudo -n probes of how sudo resolves omarchy-* commands.
      allow = [
        "etc-sysconf"
        "sudo"
      ];
    };
    omarchy-reminder = {
      class = "user-safe";
      # systemctl --user stop/list-timers on per-user omarchy-reminder-*.timer
      # units — user scope only.
      allow = [ "systemctl-user" ];
    };
    omarchy-restart-audio = {
      class = "user-safe";
      # systemctl --user restart/kill/start of pipewire+wireplumber USER
      # services — upstream's audio-recovery action — plus `sudo usbreset`
      # of a stuck USB audio device (transient device state).
      allow = [
        "sudo"
        "systemctl-user"
      ];
    };
    omarchy-restart-xcompose = {
      class = "user-safe";
      # systemctl --user stop/start of the per-user omarchy-fcitx5 unit.
      allow = [ "systemctl-user" ];
    };
    omarchy-update-time = {
      class = "user-safe";
      # Transient `sudo systemctl restart systemd-timesyncd` to force a clock
      # sync (upstream intent of menu update.time). No persistent config is
      # touched; timesyncd itself runs declaratively on NixOS.
      allow = [
        "sudo"
        "systemctl-restart"
      ];
    };
    # v4.0.0: persist the Bluetooth adapter power state via an rfkill soft
    # block (the state systemd-rfkill restores from /var/lib/systemd-rfkill
    # at boot) instead of forcing the adapter off every time. Transient
    # device state, no persistent system config is touched.
    omarchy-bluetooth-power = {
      class = "user-safe";
      allow = [ "rfkill" ];
    };
    # v4.0.0 restart helpers: transient rfkill unblock (+ nmcli radio/scan
    # for wifi, both runtime device state). No persistent config touched.
    omarchy-restart-bluetooth = {
      class = "user-safe";
      allow = [ "rfkill" ];
    };
    omarchy-restart-wifi = {
      class = "user-safe";
      allow = [
        "rfkill"
        "nmcli-radio"
      ];
    };
    # Privileged, but on state NixOS does not own declaratively:
    # - LUKS keyslots: `sudo cryptsetup luksChangeKey` (boot.initrd.luks only
    #   unlocks with whatever passphrase the header holds).
    omarchy-drive-password = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # - transient device state: Apple Studio Display brightness through
    #   asdcontrol (packaged here) on the hiddev node.
    omarchy-brightness-display-apple = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # - runtime container state: `sudo docker run` of dev databases on the
    #   declaratively enabled docker daemon, and `pkexec lazydocker` (a TUI
    #   on the docker socket).
    omarchy-install-docker-dbs = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    omarchy-launch-docker-tui = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # - read-only: the firmware's MSDM table (Windows product key).
    omarchy-windows-key = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # - the sudo timestamp itself (sudo -v + keepalive loop).
    omarchy-sudo-keepalive = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # v4.0.0: crash-capture on/off — a user toggle file plus starting/stopping
    # the per-user omarchy-crash-watch unit (user scope only).
    omarchy-toggle-crash-capture = {
      class = "user-safe";
      allow = [ "systemctl-user" ];
    };
  };

  # Non-bin files in the scan (install/user/**, default/bash/fns/*), by
  # path relative to the omarchy root; same classes and `allow` rules.
  files = {
    # first-run: enables the per-user units; patched in pkgs/omarchy.nix so
    # owed.service (owe can be excluded) is only enabled when it exists.
    "install/user/first-run/enable-user-units.sh" = {
      class = "nixos-adapted";
      allow = [ "systemctl-user" ];
    };
    # Read-only probe of /etc/pam.d/omarchy-lock-fingerprint (the module
    # writes it when omarchy.fingerprint.enable is set); "Enable sudo and
    # unlocking" is notification prose. The invitation leads to the
    # declarative-note stub of omarchy-setup-security-fingerprint.
    "install/user/first-run/setup-fingerprint.hook" = {
      class = "user-safe";
      allow = [
        "etc-sysconf"
        "sudo"
      ];
    };
    # ASUS ROG + ALC285 only: amixer levels and a best-effort
    # `sudo alsactl store` (|| true) of the mixer state — runtime ALSA
    # state, not NixOS-owned config.
    "install/user/hardware/asus/fix-mic.sh" = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
    # Read-only probe of /etc/modprobe.d/nvidia.conf (absent on NixOS: the
    # lspci driver check decides); writes only ~/.config/hypr.
    "install/user/hardware/fix-nouveau-cursor.sh" = {
      class = "user-safe";
      allow = [
        "etc-sysconf"
        "modprobe"
      ];
    };
    # iso2sd / format-drive shell functions: sudo dd/wipefs/parted/mkfs on
    # a removable drive the user names — explicit user actions on media,
    # not system state.
    "default/bash/fns/drives" = {
      class = "user-safe";
      allow = [ "sudo" ];
    };
  };

  # Menu entries deleted from default/omarchy/omarchy-menu.jsonc at package
  # time (their scripts are declarative-note stubs; no NixOS runtime
  # implementation exists).
  hiddenMenuIds = [
    "setup.direct-boot"
    "setup.security.fido2"
    "setup.security.passwordless-sudo"
    "remove.security.fido2"
    "trigger.hardware.hybrid-gpu"
    "update.config.plymouth"
    "style.unlock"
    "update.timezone"
    # AUR-only browsers (zen-browser-bin, brave-origin-bin) — not in nixpkgs,
    # and their installer scripts also mutate /etc policy dirs (stubbed).
    "install.browser.zen"
    "install.browser.brave-origin"
    "remove.browser.zen"
    "remove.browser.brave-origin"
    # v4.0.0 Setup > Reset Computer: btrfs @factory snapshot + limine ISO
    # machinery (omarchy-system-factory-reset is a declarative-note stub);
    # NixOS rolls back via boot generations.
    "setup.reset"
    # v4.0.2 Setup/Remove > Security > Sudoless Docker: usermod/gpasswd docker
    # (stubbed declarative-note — group membership is users.users.<name>.
    # extraGroups on NixOS, with the same passwordless-root warning).
    "setup.security.sudoless-docker"
    "remove.security.sudoless-docker"
    # Setup > Network > DNS: omarchy-dns writes /etc/NetworkManager and
    # /etc/systemd/resolved.conf imperatively (stubbed declarative-note);
    # DNS on NixOS is services.resolved / networking.nameservers.
    "setup.network.dns"
    "setup.network.dns.dhcp"
    "setup.network.dns.cloudflare"
    "setup.network.dns.google"
    "setup.network.dns.custom"
    # 8b4eae6 Setup/Remove > SSH Agent: gcr-ssh-agent is enabled declaratively
    # (services.gnome.gcr-ssh-agent); both scripts are declarative-note stubs.
    "setup.security.ssh-agent"
    "remove.service.ssh-agent"
  ];
}
