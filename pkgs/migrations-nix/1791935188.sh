echo "Stop browsers asking to be the default behind Omarchy's link routing"

# NixOS adapter of 1791935188: keep the user-scope flags.conf appends; the
# root half (managed-policy writes under /etc/*/policies and Firefox
# distribution dirs via install/helpers/browser-policy.sh) is dropped —
# browser policy directories are owned by the NixOS module system
# (programs.chromium.policies / environment.etc). The xdg default-browser
# association this guards is already Omarchy-managed via xdg-settings.
for flags_file in "$HOME"/.config/{chromium,chrome,microsoft-edge-stable,brave,brave-origin}-flags.conf; do
  [[ -f $flags_file ]] || continue
  grep -qxF -- '--no-default-browser-check' "$flags_file" && continue

  [[ -n $(tail -c1 "$flags_file") ]] && echo >>"$flags_file"
  echo '--no-default-browser-check' >>"$flags_file"
done
