#!/bin/bash
# Claude Desktop launcher — taken from omacom/omarchy-pkgs (MIT),
# pkgbuilds/claude-desktop/claude-desktop-launcher.sh. The Debian
# package's /usr/bin/claude-desktop is a bare symlink into the Electron
# tree; this launcher replaces it with flags-file + Ozone handling.
# __APP_BIN__ is substituted with the store path at package build time.
set -euo pipefail

user_flags=()
config_home="${XDG_CONFIG_HOME:-}"
[[ -n "$config_home" || -z "${HOME:-}" ]] || config_home="$HOME/.config"
flags_file="${config_home:+$config_home/claude-desktop-flags.conf}"

if [[ -n "$flags_file" && -f "$flags_file" && -r "$flags_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    [[ -n "${line//[[:space:]]/}" ]] || continue
    read -r -a flags <<<"$line"
    user_flags+=("${flags[@]}")
  done <"$flags_file"
fi

# Chromium's own Ozone detection falls back to XWayland often enough to matter,
# and the result is a blurry window on every scaled display. Ask for Wayland
# directly, unless the user has already picked a platform themselves.
platform_flags=()
if [[ -n "${WAYLAND_DISPLAY:-}" || "${XDG_SESSION_TYPE:-}" == wayland ]]; then
  platform_flags=(--ozone-platform=wayland)

  for flag in "${user_flags[@]}" "$@"; do
    case "$flag" in
      --ozone-platform=* | --ozone-platform-hint=*) platform_flags=() ;;
    esac
  done
fi

exec __APP_BIN__ "${platform_flags[@]}" "${user_flags[@]}" "$@"
