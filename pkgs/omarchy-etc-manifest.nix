# Classification manifest for upstream's Arch /etc overlay (the omarchy-src
# etc/ tree, which the Arch ISO installer copies to /etc). On NixOS the
# module declares the equivalents instead; checks.omarchy-etc-parity fails
# the build when upstream adds or removes a file until it is classified
# here (fail-closed, same doctrine as pkgs/omarchy-migrations.nix).
#
# Classes:
#   native   — declared as a native NixOS option in the "Upstream /etc
#              defaults" block of modules/nixos/default.nix
#   vendored — shipped verbatim via environment.etc ... .source from the
#              vendored package ($out/share/omarchy/etc)
#   seed     — per-user mutable seed via the home-manager module
#   covered  — satisfied by an already-existing mechanism (see comment)
#   na       — Arch-stack specific, no NixOS counterpart (reason in comment)
{
  # v4.0.3: mise tool_alias config exposing Cursor's launcher without its
  # bundled Node (mise model rejected — the catalog is final).
  "mise/conf.d/omarchy.toml" = "na";
  "mise/conf.d/omarchy-agent-accounts.toml" = "na"; # mise dispatch is not used; the package supplies NixOS agent account wrappers on the session PATH
  # v4.0.2: upstream hardened the CUPS account separation and then removed
  # automatic printer discovery entirely (migration 1788009111 drops
  # cups-browsed). NixOS matches: services.printing stays on, browsed is
  # disabled in the module. The cups-browsed.conf contents changed to a
  # CacheDir/Driverless-only setup for the day upstream re-enables it.
  "cups/cups-browsed.conf" = "na";
  "cups/cups-files.conf" = "na"; # dedicated cups-browsed account (User/Group 209, SystemGroup cups-browsed) — nixpkgs CUPS unit owns its user natively
  "sysusers.d/omarchy-cups-browsed.conf" = "na"; # systemd-sysusers for the Arch cups-browsed account; users.users is declarative on NixOS
  "systemd/system/cups-browsed.service.d/10-omarchy.conf" = "na"; # Arch cups-browsed unit override; service not shipped (discovery removed)
  "docker/daemon.json" = "native"; # virtualisation.docker.daemon.settings — log rotation only; dns/bip pins deliberately dropped (no resolved bridge integration on NixOS)
  "fastfetch/config.jsonc" = "seed"; # HM seed ~/.config/fastfetch/config.jsonc
  "gnupg/dirmngr.conf" = "vendored"; # environment.etc."gnupg/dirmngr.conf"
  "limine-entry-tool.d/omarchy-defaults.conf" = "na"; # limine bootloader config — NixOS owns boot entries
  "limine-entry-tool.d/omarchy-uki.conf" = "na"; # limine UKI toggle
  # 33783b1: mpv hardware decoding through the reliable-decoders list.
  "mpv/mpv.conf" = "vendored"; # environment.etc."mpv/mpv.conf" — mpv's system config layer (~/.config/mpv overrides)
  "mkinitcpio.conf.d/omarchy_hooks.conf" = "na"; # Arch mkinitcpio initrd hooks — NixOS builds its own initrd
  "mkinitcpio.conf.d/00-omarchy-hooks.conf" = "na"; # platform-specific Arch HOOKS baseline; boot.initrd owns the NixOS initrd
  "mkinitcpio.conf.d/thunderbolt_module.conf" = "na"; # Arch early-module probe; boot.initrd.availableKernelModules is consumer-owned, services.hardware.bolt covers userspace
  "modprobe.d/omarchy-usb-autosuspend.conf" = "native"; # boot.extraModprobeConfig (usbcore autosuspend=-1)
  "NetworkManager/conf.d/omarchy-wifi-powersave.conf" = "native"; # networking.networkmanager.wifi.powersave
  "nsswitch.conf" = "na"; # nixpkgs generates nsswitch.conf from system.nssModules; services.avahi nssmdns4 covers mdns_minimal
  "plymouth/plymouthd.conf" = "native"; # boot.plymouth.theme = "omarchy"
  "profile.d/omarchy.sh" = "covered"; # env-bootstrap deliberately NOT sourced (Arch dev-link logic); same effect via sessionVariables + uwsm env.d — docs/UPSTREAM.md
  "sddm.conf.d/10-theme.conf" = "native"; # services.displayManager.sddm.theme
  "sddm.conf.d/10-wayland.conf" = "native"; # sddm.wayland.enable + Wayland.CompositorCommand
  "security/faillock.conf" = "covered"; # deny=10 passed inline in security.pam.services.omarchy-lock-password
  # v4.0.1 removed sudoers.d/omarchy-asdcontrol (df819a6f closed the
  # passwordless path to root): upstream's brightness script now uses plain
  # `sudo asdcontrol` and takes the prompt. Same on NixOS.
  "sudoers.d/omarchy-passwd-tries" = "native"; # security.sudo.extraConfig (passwd_tries=10)
  "sudoers.d/omarchy-dns" = "na"; # passwordless omarchy-dns provider switch — DNS is declarative (omarchy-dns is a stub; services.resolved / networking.nameservers)
  # 33783b1: passwordless omarchy-locale-generate for the 50-language menu;
  # NixOS generates locales declaratively (i18n.supportedLocales) and
  # omarchy-locale-generate is a declarative-note stub — the grant would
  # never fire.
  "sudoers.d/omarchy-locale-generate" = "na";
  "sudoers.d/omarchy-theme-browser" = "na"; # passwordless browser-accent policy write — /etc browser policy dirs are module-owned on NixOS (omarchy-theme-set-browser is a no-op stub)
  "sudoers.d/omarchy-tzupdate" = "native"; # security.sudo.extraRules (only NOPASSWD timedatectl set-timezone with upstream's anchored single-argument regex)
  "sysctl.d/90-omarchy-arp.conf" = "native"; # boot.kernel.sysctl (arp_ignore/arp_announce — dock Ethernet + Wi-Fi on one network)
  "sysctl.d/90-omarchy-file-watchers.conf" = "covered"; # nixpkgs config/sysctl.nix already ships the identical fs.inotify.max_user_watches=524288 mkDefault
  "sysctl.d/99-omarchy-sysctl.conf" = "native"; # boot.kernel.sysctl (zram-era VM tuning + tcp_mtu_probing)
  "systemd/logind.conf.d/10-ignore-power-button.conf" = "native"; # services.logind.settings.Login.HandlePowerKey = "ignore"
  "systemd/logind.conf.d/20-inhibit-delay.conf" = "native"; # services.logind.settings.Login.InhibitDelayMaxSec = 15
  "systemd/oomd.conf.d/10-omarchy.conf" = "vendored"; # environment.etc."systemd/oomd.conf.d/10-omarchy.conf"
  "systemd/resolved.conf.d/10-disable-multicast.conf" = "na"; # systemd-resolved not enabled on NixOS (NetworkManager owns DNS); LLMNR/mDNS are off by resolved simply not running
  "systemd/resolved.conf.d/20-docker-dns.conf" = "na"; # resolved bridge listener not in use; docker defaults pass the host resolver through to containers
  "systemd/system.conf.d/10-faster-shutdown.conf" = "native"; # systemd.settings.Manager.DefaultTimeoutStopSec = "5s"
  "systemd/system.conf.d/20-mount-events.conf" = "native"; # systemd.settings.Manager.ManagerEnvironment (SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST=30)
  "systemd/system.conf.d/20-omarchy-nofile.conf" = "native"; # systemd.settings.Manager.DefaultLimitNOFILE
  "systemd/system/docker.service.d/no-block-boot.conf" = "native"; # systemd.services.docker.unitConfig.DefaultDependencies = false
  # 33783b1 binfmt plumbing: nixpkgs' own systemd-binfmt.service and
  # proc-sys-fs-binfmt_misc.mount own registration on NixOS; the port's
  # cross-arch execution is the opt-in omarchy.binfmtEmulatedSystems.
  "systemd/system/proc-sys-fs-binfmt_misc.mount.d/10-omarchy-conditions.conf" = "na";
  "systemd/system/systemd-binfmt.service.d/10-eager-mount.conf" = "na";
  # (polkit-1/rules.d/40-omarchy-{usb,thunderbolt}.rules,
  # systemd/system/bolt.service.d/omarchy-authorization.conf and
  # systemd/system/omarchy-thunderbolt-authorization.service were fully
  # reverted upstream at 33783b1 with the approval feature.)
  "systemd/system/plocate-updatedb.service.d/ac-only.conf" = "native"; # services.locate (plocate) + systemd.services.update-locatedb ConditionACPower (nixpkgs unit name)
  "systemd/system/user@.service.d/10-faster-shutdown.conf" = "native"; # systemd.services."user@".serviceConfig.TimeoutStopSec = "5s"
  "systemd/user.conf.d/20-omarchy-nofile.conf" = "native"; # systemd.user.settings.Manager (post-26.05) / systemd.user.extraConfig (26.05) DefaultLimitNOFILE — version-dependent
  "systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf" = "native"; # systemd.user.services."wayland-wm@hyprland.desktop".serviceConfig.KillMode = "mixed"
  "tmpfiles.d/omarchy-nopasswd-sudo.conf" = "na"; # boot-time cleanup of transient sudoers grants — the NixOS probe/config adapter never writes a grant
  "tmpfiles.d/omarchy-zswap.conf" = "native"; # systemd.tmpfiles.rules: w! zswap enabled=N (boot-only)
  "udev/rules.d/60-omarchy-io-scheduler.rules" = "native"; # services.udev.extraRules (kyber on whole disks nvme*/sd*/mmcblk*/vd*; partitions and zram carry no scheduler)
  "xdg/kitty/kitty.conf" = "vendored"; # environment.etc."xdg/kitty/kitty.conf" — v4.0.3 moved kitty's base defaults here; the user seed became a thin include/override file on top
  # 33783b1: Omarchy's own XKB option (Caps Lock + Shift = Compose). The
  # rules file includes the system rules via %S and appends the option;
  # libxkbcommon searches /etc/xkb ahead of its compiled-in root, which is
  # exactly the mechanism upstream relies on (see modules/nixos).
  "xkb/rules/evdev" = "vendored"; # environment.etc."xkb/rules/evdev"
  "xkb/symbols/omarchy" = "vendored"; # environment.etc."xkb/symbols/omarchy"
}
