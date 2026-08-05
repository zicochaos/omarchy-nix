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
  "cups/cups-browsed.conf" = "native"; # services.printing.browsedConf (CreateRemotePrinters Yes)
  "docker/daemon.json" = "native"; # virtualisation.docker.daemon.settings — log rotation only; dns/bip pins deliberately dropped (no resolved bridge integration on NixOS)
  "fastfetch/config.jsonc" = "seed"; # HM seed ~/.config/fastfetch/config.jsonc
  "gnupg/dirmngr.conf" = "vendored"; # environment.etc."gnupg/dirmngr.conf"
  "limine-entry-tool.d/omarchy-defaults.conf" = "na"; # limine bootloader config — NixOS owns boot entries
  "limine-entry-tool.d/omarchy-uki.conf" = "na"; # limine UKI toggle
  "mkinitcpio.conf.d/omarchy_hooks.conf" = "na"; # Arch mkinitcpio initrd hooks — NixOS builds its own initrd
  "mkinitcpio.conf.d/thunderbolt_module.conf" = "na"; # initrd module list; kernel autoloads thunderbolt, services.hardware.bolt covers userspace
  "modprobe.d/omarchy-usb-autosuspend.conf" = "native"; # boot.extraModprobeConfig (usbcore autosuspend=-1)
  "NetworkManager/conf.d/omarchy-wifi-powersave.conf" = "native"; # networking.networkmanager.wifi.powersave
  "nsswitch.conf" = "na"; # nixpkgs generates nsswitch.conf from system.nssModules; services.avahi nssmdns4 covers mdns_minimal
  "plymouth/plymouthd.conf" = "native"; # boot.plymouth.theme = "omarchy"
  "profile.d/omarchy.sh" = "covered"; # env-bootstrap deliberately NOT sourced (Arch dev-link logic); same effect via sessionVariables + uwsm env.d — docs/UPSTREAM.md
  "sddm.conf.d/10-theme.conf" = "native"; # services.displayManager.sddm.theme
  "sddm.conf.d/10-wayland.conf" = "native"; # sddm.wayland.enable + Wayland.CompositorCommand
  "security/faillock.conf" = "covered"; # deny=10 passed inline in security.pam.services.omarchy-lock-password
  "sudoers.d/omarchy-asdcontrol" = "native"; # security.sudo.extraRules (NOPASSWD asdcontrol, profile path)
  "sudoers.d/omarchy-passwd-tries" = "native"; # security.sudo.extraConfig (passwd_tries=10)
  "sudoers.d/omarchy-tzupdate" = "native"; # security.sudo.extraRules (NOPASSWD tzupdate + timedatectl set-timezone)
  "sysctl.d/90-omarchy-file-watchers.conf" = "covered"; # nixpkgs config/sysctl.nix already ships the identical fs.inotify.max_user_watches=524288 mkDefault
  "sysctl.d/99-omarchy-sysctl.conf" = "native"; # boot.kernel.sysctl (zram-era VM tuning + tcp_mtu_probing)
  "systemd/logind.conf.d/10-ignore-power-button.conf" = "native"; # services.logind.settings.Login.HandlePowerKey = "ignore"
  "systemd/logind.conf.d/20-inhibit-delay.conf" = "native"; # services.logind.settings.Login.InhibitDelayMaxSec = 15
  "systemd/oomd.conf.d/10-omarchy.conf" = "vendored"; # environment.etc."systemd/oomd.conf.d/10-omarchy.conf"
  "systemd/resolved.conf.d/10-disable-multicast.conf" = "na"; # systemd-resolved not enabled on NixOS (NetworkManager owns DNS); LLMNR/mDNS are off by resolved simply not running
  "systemd/resolved.conf.d/20-docker-dns.conf" = "na"; # resolved bridge listener not in use; docker defaults pass the host resolver through to containers
  "systemd/system.conf.d/10-faster-shutdown.conf" = "native"; # systemd.settings.Manager.DefaultTimeoutStopSec = "5s"
  "systemd/system.conf.d/20-omarchy-nofile.conf" = "native"; # systemd.settings.Manager.DefaultLimitNOFILE
  "systemd/system/docker.service.d/no-block-boot.conf" = "native"; # systemd.services.docker.unitConfig.DefaultDependencies = false
  "systemd/system/plocate-updatedb.service.d/ac-only.conf" = "native"; # services.locate (plocate) + systemd.services.update-locatedb ConditionACPower (nixpkgs unit name)
  "systemd/system/user@.service.d/10-faster-shutdown.conf" = "native"; # systemd.services."user@".serviceConfig.TimeoutStopSec = "5s"
  "systemd/user.conf.d/20-omarchy-nofile.conf" = "native"; # systemd.user.settings.Manager (post-26.05) / systemd.user.extraConfig (26.05) DefaultLimitNOFILE — version-dependent
  "tmpfiles.d/omarchy-zswap.conf" = "native"; # systemd.tmpfiles.rules: w! zswap enabled=N (boot-only)
}
