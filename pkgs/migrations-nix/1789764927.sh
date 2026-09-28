echo "Enable OWE desktop video backgrounds and lock feed"

# NixOS: owe ships through omarchy.appPackages (the module registers
# owed.service and links share/owe); there is no pkg-add step and no
# /usr/lib/systemd/user fallback link. An excluded owe leaves nothing to do.
if ! systemctl --user cat owed.service >/dev/null 2>&1; then
  echo "NixOS: owed.service is not installed (owe excluded); skipping"
  exit 0
fi

omarchy-hook-install theme-set /run/current-system/sw/share/owe/10-owe-sync

systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user enable owed.service

# A TTY update enables the next graphical login without starting a renderer
# against a missing Wayland session. A failed live start leaves this pending.
if [[ ${OMARCHY_UPGRADE_TO_QUATTRO_LIVE:-0} != 1 ]] && systemctl --user is-active --quiet graphical-session.target; then
  systemctl --user start owed.service
fi
