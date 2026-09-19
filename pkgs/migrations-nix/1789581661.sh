echo "Install Elsewhen, the world clock plugin"

# NixOS adapter: the plugin is not an Arch package here — pkgs/elsewhen.nix
# ships it inside the omarchy package at $OMARCHY_PATH/plugins/omacom.elsewhen
# (the analogue of the elsewhen package's /usr/share/omarchy/plugins on Arch).
# The omarchy-pkg-add step is dropped; the plugin link, the shell rescan and
# the bar placement keep upstream mechanics. The home-manager module manages
# the same ~/.config link (refreshed to the active generation on every
# switch); this link step covers a home that migrates before HM links it, and
# preserves existing real dirs and symlinks exactly like upstream.

plugin="$HOME/.config/omarchy/plugins/omacom.elsewhen"
plugin_source="${OMARCHY_PATH:-/run/current-system/sw/share/omarchy}/plugins/omacom.elsewhen"
mkdir -p "$(dirname "$plugin")"
if [[ ! -e $plugin && ! -L $plugin ]]; then
  ln -s "$plugin_source" "$plugin"
fi

# A live shell must rescan to discover the plugin; an absent one has nothing
# in memory to rescan — it scans ~/.config/omarchy/plugins at startup — so the
# call is skipped. Upstream can run rescan unconditionally because
# omarchy-update migrates with the session alive; on NixOS the login-time
# omarchy-migrate unit runs before the session, and an unconditional call
# would leave the migration pending forever. A failing rescan on a live shell
# still fails the migration (stays pending, retried), like upstream.
if omarchy-shell shell listPlugins >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins
fi

# Absent-shell is carried on inside omarchy-bar itself (upstream semantics);
# a live shell dedupes/moves the entry.
omarchy-bar put omacom.elsewhen --before omarchy.clock
