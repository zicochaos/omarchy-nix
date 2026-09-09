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
  # yt-dlp chromium ext: the package part is declarative (module ships
  # yt-dlp); the flags rewrite + native messaging host registration are the
  # user-scope remainder.
  "1780517689.sh" = "adapter";

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
  "1785543725.sh" = "user-safe"; # WhatsApp Slim ext in *-flags.conf ($HOME only)
  "1785608166.sh" = "user-safe"; # omarchy-sleep-lock drop-in in ~/.config/systemd/user + systemctl --user
  "1785633225.sh" = "user-safe"; # foot.ini scrollback multiplier ($HOME only)
  # v4.0.0 wave:
  "1785591762.sh" = "user-safe"; # WhatsApp Slim ext in brave-origin flags ($HOME only)
  "1786098807.sh" = "user-safe"; # relink agent skill symlinks to default/agents/skills/
  #                           # (HM manages the same links; ln -sfn is idempotent and
  #                           # refreshes pre-HM installs)
  "1786099804.sh" = "user-safe"; # rename model-usage bar widget -> agents via jq ($HOME)
  "1786279107.sh" = "user-safe"; # add keyboard-layout widget to bar layout (omarchy-bar put)
  "1786451567.sh" = "user-safe"; # repair theme symlinks (literal ~ targets, $HOME)
  "1786517850.sh" = "user-safe"; # drop retired notification image cache ($HOME)
  "1786549201.sh" = "user-safe"; # install the pick-a-default-agent invitation hook ($HOME)
  "1786643346.sh" = "user-safe"; # Copy URL shortcut re-registration (Chromium profile, $HOME)
  "1786782461.sh" = "user-safe"; # remove literal \n[text-bindings] line in foot.ini ($HOME)
  # v4.0.1/v4.0.2 wave:
  "1787481315.sh" = "user-safe"; # re-stage the current theme to drop installed-theme code
  #                           # (theme staging is $HOME-only; missing theme falls back
  #                           # to omarchy-theme-set "Tokyo Night", also $HOME)
  "1787618700.sh" = "user-safe"; # input-device toggles: generated Lua -> plain name file
  #                           # ($HOME/.local/state) + hyprctl reload
  "1787843905.sh" = "user-safe"; # link omarchy agent skills into ~/.hermes/skills
  #                           # (ln -sfn, idempotent; same model as 1786098807)
  "1788595060.sh" = "user-safe"; # Chromium copy-url + ytdlp native messaging hosts for
  #                           # Brave Origin ($HOME registration; browser not packaged on
  #                           # NixOS, so the hosts simply never load)

  # ------------------------------------------------------------------- skip
  "1778623107.sh" = "skip"; # mpv-mpris via omarchy-pkg-add (pacman)
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
  "1784568652.sh" = "skip"; # mask NetworkManager-wait-online — native in the module
  #                           # (systemd.services.NetworkManager-wait-online.enable = false)
  "1784672586.sh" = "skip"; # quickshell-git via pacman (we ship nixpkgs quickshell)
  # v4.0.3: 1784809451 (/etc/updatedb.conf + plocate restart) was dropped
  # upstream, superseded by the plocate-updatedb.service.d drop-in (vendored,
  # system unit — services.locate is native here)
  "1784809452.sh" = "skip"; # snapper timeline cleanup (Arch/Btrfs snapper)
  "1784818437.sh" = "skip"; # PAM fingerprint lid gate (NixOS PAM is declarative)
  "1784909971.sh" = "skip"; # mise wrapper regen (mise model rejected — catalog is final)
  "1784914435.sh" = "skip"; # NM wifi powersave — native in the module
  #                           # (networking.networkmanager.wifi.powersave = false)
  "1784917531.sh" = "skip"; # limine initramfs_async=0 kernel cmdline (Arch boot)
  "1784960000.sh" = "skip"; # XPS speaker tuning via omarchy-pkg-add (pacman)
  "1784961000.sh" = "skip"; # zram sysctl apply + dev-zram0.swap restart — native in the
  #                           # module (boot.kernel.sysctl, etc/sysctl.d/99-omarchy-sysctl.conf
  #                           # parity; zramSwap owns the device)
  "1784970000.sh" = "skip"; # logind InhibitDelay drop-in — native in the module
  #                           # (services.logind.settings.Login.InhibitDelayMaxSec = 15)
  "1785013000.sh" = "skip"; # archinstall zram-generator.conf leftover (N/A on NixOS)
  "1785090473.sh" = "skip"; # libfprint-git->libfprint via pacman
  "1785095882.sh" = "skip"; # notify user-units switch; module enables omarchy-migrate-notify natively
  "1785167800.sh" = "skip"; # fcitx5 supervision; module enables omarchy-fcitx5 natively
  "1785273276.sh" = "skip"; # T2 Mac apple-bce->t2bce mkinitcpio/limine-update (Arch boot)
  "1785351479.sh" = "skip"; # pacman -Rns kvantum/kvantum-qt5 (Arch package mutation; the intent —
  #                           # drop kvantum from Qt theming — is applied declaratively in the
  #                           # omarchy-src bump)
  "1785424256.sh" = "skip"; # systemd-oomd enable (native in the module: systemd.oomd.enable
  #                           # + vendored oomd.conf.d / app.slice.d drop-ins via environment.etc)
  "1785511354.sh" = "skip"; # qrencode via omarchy-pkg-add (pacman; module ships qrencode)
  "1785608251.sh" = "skip"; # ddcutil via omarchy-pkg-add (pacman; module ships ddcutil + hardware.i2c)
  "1785617047.sh" = "skip"; # omp via mise wrapper (mise model rejected — catalog is final;
  #                           # oh-my-pi is not in nixpkgs, menu entry hidden)
  "1785637426.sh" = "skip"; # omacalc/gnome-calculator swap via pacman (declarative: module ships
  #                           # omacalc and dropped gnome-calculator)
  "1785846769.sh" = "skip"; # agent mise wrappers (mise model rejected — agents install via the
  #                           # nix catalog: Menu > Install > AI)
  # v4.0.0 wave:
  "1785944594.sh" = "skip"; # T2 Mac suspend/fan defaults: limine + t2fand /etc writes (Arch boot)
  "1786137597.sh" = "skip"; # re-runs 1785944594 (same Arch-boot target)
  "1786181929.sh" = "skip"; # PAM env PATH for SSH commands (/etc/pam.d; NixOS owns PAM)
  "1786273938.sh" = "skip"; # herdr install via omarchy-pkg-add + repo (declarative: module ships
  #                           # pkgs/herdr.nix via appPackages)
  "1786278735.sh" = "skip"; # /etc/ssh/ssh_config.d keepalive (declarative: programs.ssh, below)
  "1786355450.sh" = "skip"; # ttfx swap via omarchy-pkg-add (declarative: appPackages)
  "1786380259.sh" = "skip"; # /etc/bluetooth/main.conf AutoEnable + rfkill machine-wide state
  #                           # (declarative: hardware.bluetooth + systemd-rfkill)
  "1786386460.sh" = "skip"; # libvips via omarchy-pkg-add (declarative: module ships vips)
  "1786391100.sh" = "skip"; # brcmfmac WPA supplicant quirk (Arch install-time fixup)
  "1786447584.sh" = "skip"; # zbar via omarchy-pkg-add (declarative: module ships zbar)
  "1786482992.sh" = "skip"; # Limine kernel-cmdline boot image rebuild (Arch boot)
  "1786539345.sh" = "skip"; # crash-watch setup — the user unit is shipped + enabled natively
  #                           # (modules/nixos default.nix block H); no runtime setup needed
  "1786567036.sh" = "skip"; # unmask wpa_supplicant (iwd-era carryover; NixOS ships NM + supplicant)
  "1786605598.sh" = "skip"; # initramfs rebuild for NVIDIA nouveau firmware (mkinitcpio)
  "1786952219.sh" = "skip"; # mise -> mise-bin repo swap (mise model rejected — catalog is final)
  "1786183928.sh" = "skip"; # regenerate mise tool wrappers (mise model rejected — catalog is final;
  #                           # omarchy-refresh-applications itself stays user-safe)
  # v4.0.1/v4.0.2 wave:
  "1786719479.sh" = "skip"; # Gemini -> Antigravity via omarchy-mise-install (mise model rejected;
  #                           # no NixOS install ever had a gemini mise wrapper or the agent file
  #                           # set to gemini, so every branch is a no-op here)
  "1787133200.sh" = "skip"; # qt6-imageformats via omarchy-pkg-add (declarative: module ships
  #                           # qt6.qtimageformats for webp theme backgrounds)
  "1787215824.sh" = "skip"; # hey via mise wrapper (mise model rejected; hey-cli not in nixpkgs)
  "1787342993.sh" = "skip"; # ori via mise wrapper (mise model rejected; ori not in nixpkgs)
  "1787399318.sh" = "skip"; # quickshell-git -> quickshell via pacman (module ships nixpkgs
  #                           # quickshell; upstream 0.3.1 switch-back is what we already run)
  "1787494718.sh" = "skip"; # FIDO2 authfile ownership in /etc/fido2 (security.pam.u2f owns the
  #                           # authfile declaratively on NixOS)
  "1787515927.sh" = "skip"; # browser policy dir hardening under /etc (module-owned on NixOS)
  "1787573629.sh" = "skip"; # regenerate mise wrappers with --quiet (mise model rejected)
  "1787580187.sh" = "skip"; # docker group opt-out: gpasswd + Docker.desktop refresh (group
  #                           # membership is users.users.<name>.extraGroups on NixOS; the port
  #                           # never put anyone in docker by default)
  "1787589206.sh" = "skip"; # pacman SigLevel for the [omarchy] repo (pacman)
  "1787666837.sh" = "skip"; # Dell XPS 13 sidecar amps: pkg-add + sudo apply (Arch firmware
  #                           # tooling, dell-xps13-sidecar-amps not in nixpkgs)
  "1787691200.sh" = "skip"; # Chromium first-run EULA seed at /usr/lib/chromium (store path is
  #                           # immutable; nixpkgs chromium answers its own first run)
  "1787760281.sh" = "skip"; # Hermes CLI wrapper via mise (mise model rejected; hermes not in
  #                           # nixpkgs — its menu entries stay behind omarchy-pkg-present guards)
  "1787815267.sh" = "skip"; # CUPS account separation: pacman + systemctl + sysusers (CUPS is
  #                           # services.printing on NixOS)
  "1787865477.sh" = "skip"; # drop the input group grant via gpasswd (users.users is declarative;
  #                           # NixOS never granted input group-wide)
  "1788009111.sh" = "skip"; # remove cups-browsed + implicitclass queues (declarative: the module
  #                           # sets services.printing.browsed.enable = false, same v4.0.2 intent)
  "1788025225.sh" = "skip"; # remove privileged files from retired Omarchy installers
  #                           # (/etc/sudoers.d, /etc/systemd leftovers — never existed on NixOS)
  "1788102906.sh" = "skip"; # Omarchy 3 legacy XCompose include + power udev rules (Omarchy 3
  #                           # artifacts never existed on NixOS installs)
  "1788112314.sh" = "skip"; # rc channel pacman repo pointers (pacman)
  "1788124236.sh" = "skip"; # sshd password-auth hardening via /etc/ssh drop-in (services.openssh
  #                           # is declarative; omarchy-setup-security-sshd is nixos-adapted)
  "1788596255.sh" = "skip"; # vi via omarchy-pkg-add (declarative: module ships nvi as the `vi`
  #                           # command; the pin has no `vi` attr)
  # --- v4.0.3 wave ---
  "1786609204.sh" = "skip"; # qt6-multimedia via omarchy-pkg-add (declarative: module ships
  #                           # qt6.qtmultimedia — native video wallpaper playback)
  "1787215483.sh" = "skip"; # mise settings upgrade.auto_prune (mise model rejected — catalog is
  #                           # final)
  "1788577553.sh" = "skip"; # cursor-agent via mise wrapper (mise model rejected; cursor-agent
  #                           # not on the pin — setup.default.agent.cursor-agent dropped)
  "1788619462.sh" = "skip"; # Hermes theme hand-over (hermes not in nixpkgs; pkg-present
  #                           # self-gates to exit 0, and omarchy-theme-set-hermes is $HOME-only)
  "1788662350.sh" = "skip"; # repair root-owned system-sleep hooks + supergfxd drop-in
  #                           # (/usr/lib/systemd — NixOS owns system units declaratively)
  "1788724825.sh" = "skip"; # Muse Code via mise wrapper (mise model rejected; Meta's muse is
  #                           # NOT the nixpkgs `muse` attr — that is the MusE audio sequencer;
  #                           # setup.default.agent.muse dropped)
  "1788745941.sh" = "user-safe"; # Kitty config repair: stock-sha refresh via
  #                           # omarchy-refresh-config + commenting out unrestricted
  #                           # allow_remote_control ($HOME only)
  "1788848726.sh" = "skip"; # retire the legacy user icon font (guards on the Arch path
  #                           # /usr/share/fonts/omarchy/omarchy.ttf; NixOS installs never ran
  #                           # the quattro upgrader and the module ships the font declaratively)
  "1788862626.sh" = "skip"; # Elgato Cam Link 4K v4l2 relay setup (Arch hardware fixup: system
  #                           # units, udev trigger, setfacl)
}
