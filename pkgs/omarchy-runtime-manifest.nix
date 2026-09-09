# Machine-readable classification of upstream runtime commands that
# touch NixOS-owned system state, and of the menu entries that reach them.
#
# Two-tier scheme, enforced by checks.omarchy-runtime (flake.nix):
#
#   1. Every packaged bin/ script NOT listed here is verified user-safe by
#      construction: the build-time scan finds no forbidden mutation pattern
#      (pacman/ufw/systemctl enable///etc-writes/modprobe/...) in its body.
#      A NEW upstream script that mutates system state matches a pattern, is
#      missing from this manifest, and FAILS the check — classification is
#      forced at bump time. This is the fail-closed half of the scheme.
#
#   2. Every script listed here carries an explicit class:
#      - declarative-note: body fully replaced with a pointer to the NixOS
#        option that owns the state (exit 0). Scan requires ZERO hits.
#      - nixos-adapted: hand-rewritten for NixOS (system mutations removed,
#        user-state flows kept). Scan requires ZERO hits.
#      - user-safe: kept verbatim. Scan allows ONLY the declared `allow`
#        pattern groups; each entry documents why the leftover is safe.
#
# `note` is the pointer text baked into generated declarative-note stubs by
# pkgs/omarchy.nix. hiddenMenuIds are deleted from omarchy-menu.jsonc at
# package time (the scripts behind them are stubbed, so a stale caller can
# never reach a real Arch mutation).
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
      note = "There is no pacman package cache on NixOS: old generations are garbage-collected with nix-collect-garbage -d (or nix.settings.auto-optimise-store / gc.options in your flake).";
    };
    # v4.0.1: the browser-accent policy helper — its only caller
    # (omarchy-theme-set-browser) is a no-op stub on NixOS, and the helper
    # itself is stubbed in pkgs/omarchy.nix for the same reason.
    omarchy-theme-set-browser-policy = {
      class = "declarative-note";
      note = "Browser policy directories under /etc are module-owned on NixOS (programs.chromium.policies / environment.etc); the browser accent color cannot follow the theme at runtime.";
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

    # --- nixos-adapted: hand-rewritten in pkgs/omarchy.nix postPatch --------
    # (system mutations removed; user-state flows kept)
    omarchy-setup-security-sshd = {
      class = "nixos-adapted";
    };
    omarchy-remove-security-sshd = {
      class = "nixos-adapted";
    };
    omarchy-remove-dev-env = {
      class = "nixos-adapted";
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
    };
    omarchy-upload-log = {
      class = "nixos-adapted";
    };
    omarchy-theme-set-browser = {
      class = "nixos-adapted";
    };
    omarchy-update-firmware = {
      class = "nixos-adapted";
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

    # --- user-safe: kept verbatim; `allow` lists the audited leftovers ------
    # v4.0.3 AI wave. The Hermes pair is unreachable on NixOS (hermes is not
    # on the pin — the menu entries are dropped); kept verbatim with their
    # user-scope leftovers declared. OpenClaw IS installable here (catalog
    # entry install.ai.openclaw): systemctl --user disable --now of the
    # per-user openclaw-gateway unit, plus $HOME config cleanup — user scope
    # only, package removal routes into omarchy-pkg-drop.
    omarchy-install-ai-hermes = {
      class = "user-safe";
      # systemctl --user enable/start of the per-user hermes gateway unit.
      allow = [ "systemctl-user" ];
    };
    omarchy-remove-ai-hermes = {
      class = "user-safe";
      # systemctl --user disable/stop of the per-user hermes gateway unit.
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
      # modprobe -r + modprobe of intel_quicki2c: transient kernel state, an
      # upstream-designed hardware reset; no persistent config is touched.
      allow = [ "modprobe" ];
    };
    omarchy-windows-vm = {
      class = "user-safe";
      # modprobe + "sudo systemctl start docker" strings are printed hints in
      # an error dialog, never executed.
      allow = [
        "modprobe"
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
      # Read-only check of /etc/omarchy.conf (always absent on NixOS).
      allow = [ "etc-sysconf" ];
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
      # services — upstream's audio-recovery action, user scope only.
      allow = [ "systemctl-user" ];
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
      allow = [ "systemctl-restart" ];
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
    # v4.0.0: crash-capture on/off — a user toggle file plus starting/stopping
    # the per-user omarchy-crash-watch unit (user scope only).
    omarchy-toggle-crash-capture = {
      class = "user-safe";
      allow = [ "systemctl-user" ];
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
  ];
}
