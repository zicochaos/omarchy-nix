echo "Add yt-dlp download extension (Alt+Shift+D) to Chromium-based browsers"

# NixOS adapter: the package part (yt-dlp via omarchy-pkg-add) is dropped —
# yt-dlp is declarative, shipped in the module's runtime deps. What remains
# is user-scope: rewrite the Arch /usr/share/omarchy extension paths in
# existing *-flags.conf files to the NixOS system-profile path (matching the
# patched seed in config/chromium-flags.conf), make sure the omarchy
# extensions are loaded, and register the native messaging host.

EXT_PATH="/run/current-system/sw/share/omarchy/default/chromium/extensions"

for conf in chromium chrome google-chrome brave brave-beta brave-nightly brave-origin-beta microsoft-edge-stable; do
  flags="$HOME/.config/$conf-flags.conf"
  [[ -f $flags ]] || continue

  sed -i --follow-symlinks "s|/usr/share/omarchy/default/chromium/extensions|$EXT_PATH|g" "$flags"

  # Upstream semantics, one case at a time: a file already loading the yt-dlp
  # extension is done; a file loading only copy-url gets yt-dlp appended; a
  # custom --load-extension line without the omarchy extensions gets both; a
  # file without any gets the full line. Idempotent on re-run.
  if grep -q "omarchy/default/chromium/extensions/yt-dlp" "$flags"; then
    continue
  elif grep -q "omarchy/default/chromium/extensions/copy-url" "$flags"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)\$|--load-extension=\1,$EXT_PATH/yt-dlp|" "$flags"
  elif grep -q "^--load-extension=" "$flags"; then
    sed -i --follow-symlinks "s|^--load-extension=\(.*\)\$|--load-extension=\1,$EXT_PATH/copy-url,$EXT_PATH/yt-dlp|" "$flags"
  else
    echo "--load-extension=$EXT_PATH/copy-url,$EXT_PATH/yt-dlp" >>"$flags"
  fi
done

# Register the native messaging host that runs yt-dlp for the extension.
omarchy-install-chromium-ytdlp || true
