# Classification of upstream Omarchy migrations for NixOS.
#
# Every file shipped under $out/share/omarchy/migrations/*.sh MUST have a key
# here (enforced by checks.omarchy-migrations). Classes:
#
#   "skip"      — Arch/pacman/limine/snapper-specific, already covered
#                 natively by the NixOS module, or N/A on a NixOS install.
#                 Never executed; the marker is written so the migration is
#                 not retried on every update.
#   "user-safe" — touches only $HOME or `systemctl --user`; executed as-is.
#   "adapter"   — upstream intent kept, mechanics rewritten for NixOS in
#                 pkgs/migrations-nix/<name>.sh (executed INSTEAD of the
#                 vendored script).
#
# When bumping omarchy-src, new vendored migrations fail the check until
# classified here. One revision, one classification commit.
{
  # ---------------------------------------------------------------- adapters
  # nvim remote clipboard: provider file lives in the system profile, not
  # /usr/share/omarchy-nvim.
  "1781587663.sh" = "adapter";
  # tmux QoL backfill: keep the ~/.config/tmux edits + gsettings; drop the
  # pacman hardware_packages block (covered natively on NixOS).
  "1784401744.sh" = "adapter";

  # -------------------------------------------------------------- user-safe
  "1780057136.sh" = "user-safe"; # Shift+Enter CSI-u bindings in terminal configs
  "1780294774.sh" = "user-safe"; # shell.json clock format via jq
  "1781043107.sh" = "user-safe"; # theme state ~/.config/omarchy/current -> ~/.local/state
  "1781063758.sh" = "user-safe"; # hyprland.lua bootstrap entrypoint (matches our seed)
  "1781158082.sh" = "user-safe"; # relink nvim theme symlink
  "1784479832.sh" = "user-safe"; # kitty listen_on socket
  "1784508556.sh" = "user-safe"; # chromium flags: pin password-store=gnome-libsecret
  "1784763917.sh" = "user-safe"; # Copy URL native messaging host (writes $HOME only)
  "1784767406.sh" = "user-safe"; # rm obsolete voxtype toggle + hyprctl reload
  "1784989000.sh" = "user-safe"; # shell.json bar layout via jq
  "1785002349.sh" = "user-safe"; # repair nvim theme symlinks
  "1785101000.sh" = "user-safe"; # tailscale-receive user unit (shipped), tailscale-gated
  "1785166747.sh" = "user-safe"; # native messaging hosts for bundled chromium exts
  "1785189600.sh" = "user-safe"; # remove tmux alert hooks + TmuxAlert indicator
  "1785344985.sh" = "user-safe"; # shell.json bar layout via jq: insert omarchy.model-usage widget
  #                           # (idempotent, $HOME-only; HM seeds shell.json once and never
  #                           # refreshes it, so existing users need the in-place edit)

  # ------------------------------------------------------------------- skip
  "1778623107.sh" = "skip"; # mpv-mpris via omarchy-pkg-add (pacman)
  "1780517689.sh" = "skip"; # yt-dlp chromium ext: core is omarchy-pkg-add (pacman);
  #                           # host registration already covered by user-safe 1785166747
  "1780739888.sh" = "skip"; # dua-cli/dust package swap (pacman; module concern)
  "1781286586.sh" = "skip"; # satty->tensaku package swap (pacman; module concern)
  "1781485962.sh" = "skip"; # guarded by Arch stock-config SHAs; never matches NixOS seeds
  "1781793381.sh" = "skip"; # udiskie via omarchy-pkg-add (pacman; module concern)
  "1781984677.sh" = "skip"; # snapper repair: /etc/snapper + system units (Arch)
  "1782002156.sh" = "skip"; # retire systemd-networkd (system-level; NixOS is declarative)
  "1782049344.sh" = "skip"; # limine-snapper notifier — never shipped on NixOS
  "1784476564.sh" = "skip"; # mkinitcpio vconsole/LUKS layout (Arch initramfs)
  "1784510887.sh" = "skip"; # Brave Origin beta->stable via AUR helpers
  "1784521870.sh" = "skip"; # update-user-notify .path watcher — not shipped; notifier is native
  "1784568652.sh" = "skip"; # mask NetworkManager-wait-online (system-level; module concern)
  "1784672586.sh" = "skip"; # quickshell-git via pacman (we ship nixpkgs quickshell)
  "1784809451.sh" = "skip"; # /etc/updatedb.conf + plocate restart (system-level)
  "1784809452.sh" = "skip"; # snapper timeline cleanup (Arch/Btrfs snapper)
  "1784818437.sh" = "skip"; # PAM fingerprint lid gate (NixOS PAM is declarative)
  "1784909971.sh" = "skip"; # mise wrapper regen (mise model rejected — catalog is final)
  "1784914435.sh" = "skip"; # NM wifi powersave via sudo nmcli/iw (system-level)
  "1784917531.sh" = "skip"; # limine initramfs_async=0 kernel cmdline (Arch boot)
  "1784960000.sh" = "skip"; # XPS speaker tuning via omarchy-pkg-add (pacman)
  "1784961000.sh" = "skip"; # zram sysctl + dev-zram0.swap restart (native in the module)
  "1784970000.sh" = "skip"; # /etc logind InhibitDelay drop-in (system-level; module concern)
  "1785013000.sh" = "skip"; # archinstall zram-generator.conf leftover (N/A on NixOS)
  "1785090473.sh" = "skip"; # libfprint-git->libfprint via pacman
  "1785095882.sh" = "skip"; # notify user-units switch; module enables omarchy-migrate-notify natively
  "1785167800.sh" = "skip"; # fcitx5 supervision; module enables omarchy-fcitx5 natively
  "1785273276.sh" = "skip"; # T2 Mac apple-bce->t2bce mkinitcpio/limine-update (Arch boot)
  "1785351479.sh" = "skip"; # pacman -Rns kvantum/kvantum-qt5 (Arch package mutation; the intent —
  #                           # drop kvantum from Qt theming — is applied declaratively in the
  #                           # omarchy-src bump)
}
