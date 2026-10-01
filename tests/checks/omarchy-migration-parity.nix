# Migration parity: the upstream /etc defaults that migrations
# 1784568652 (NM-wait-online mask), 1784970000 (logind inhibit
# delay) and 1784914435 (Wi-Fi powersave off) apply imperatively on
# Arch must be declared natively by the module, and the vendored
# chromium-flags.conf seed must carry no Arch /usr/share path (the
# postPatch rewrite to the system-profile path).
{
  self,
  pkgs,
  system,
  ...
}:
let
  demoCfg = self.nixosConfigurations.demo.config;
  nmWaitUnit = demoCfg.systemd.units."NetworkManager-wait-online.service";
  logindConf = demoCfg.environment.etc."systemd/logind.conf".text;
  logindConfSource = demoCfg.environment.etc."systemd/logind.conf".source;
  nmConf = demoCfg.environment.etc."NetworkManager/NetworkManager.conf".source;
  omarchyPkg = self.packages.${system}.omarchy;
in
if nmWaitUnit.enable then
  throw "demo config does not mask NetworkManager-wait-online (systemd.services.NetworkManager-wait-online.enable)"
else if !(pkgs.lib.hasInfix "InhibitDelayMaxSec=15" logindConf) then
  throw "demo config logind.conf is missing InhibitDelayMaxSec=15"
else
  pkgs.runCommand "omarchy-migration-parity" { } ''
    # The masked unit is a /dev/null symlink — the file that lands
    # at /etc/systemd/system/NetworkManager-wait-online.service.
    if [ "$(readlink ${nmWaitUnit.unit}/NetworkManager-wait-online.service)" != /dev/null ]; then
      echo "NetworkManager-wait-online.service is not masked (not a /dev/null symlink)"
      exit 1
    fi
    # [connection] wifi.powersave=2 in the generated NM conf.
    if ! grep -q '^wifi\.powersave=2$' ${nmConf}; then
      echo "NetworkManager.conf is missing wifi.powersave=2"
      exit 1
    fi
    # Exact logind line (a hasInfix would also accept =150).
    if ! grep -q '^InhibitDelayMaxSec=15$' ${logindConfSource}; then
      echo "logind.conf is missing the exact InhibitDelayMaxSec=15 line"
      exit 1
    fi
    # The packaged seed carries BOTH bundled extensions on the
    # stable system-profile path, and no Arch /usr/share residue.
    if ! grep -qF -- '--load-extension=/run/current-system/sw/share/omarchy/default/chromium/extensions/copy-url,/run/current-system/sw/share/omarchy/default/chromium/extensions/yt-dlp' \
        ${omarchyPkg}/share/omarchy/config/chromium-flags.conf; then
      echo "chromium-flags.conf lost the stable-path load-extension line"
      exit 1
    fi
    if grep -q '/usr/share' ${omarchyPkg}/share/omarchy/config/chromium-flags.conf; then
      echo "chromium-flags.conf still references /usr/share:"
      grep '/usr/share' ${omarchyPkg}/share/omarchy/config/chromium-flags.conf
      exit 1
    fi
    # The native-messaging-host installers embed the stable
    # system-profile HOST_PATH (a store path in the generated
    # manifests would die on the first rebuild + GC), and the
    # adapter references the same path family.
    for f in \
      ${omarchyPkg}/share/omarchy/bin/omarchy-install-chromium-ytdlp \
      ${omarchyPkg}/share/omarchy/bin/omarchy-install-chromium-copy-url; do
      if ! grep -qF 'HOST_PATH="/run/current-system/sw/share/omarchy/bin/' "$f"; then
        echo "$f lost the stable HOST_PATH assignment"
        exit 1
      fi
    done
    if ! grep -q '/run/current-system/sw/share/omarchy' \
        ${omarchyPkg}/share/omarchy/migrations-nix/1780517689.sh; then
      echo "1780517689.sh lost the stable system-profile path"
      exit 1
    fi

    # Behavioral fixtures for the migration adapter: every
    # *-flags.conf shape it must handle, plus idempotency.
    EXT=/run/current-system/sw/share/omarchy/default/chromium/extensions
    STUB=$TMPDIR/stub
    mkdir -p "$STUB"
    printf '#!/bin/sh\nexit 0\n' > "$STUB/omarchy-install-chromium-ytdlp"
    chmod +x "$STUB/omarchy-install-chromium-ytdlp"
    export PATH="$STUB:$PATH"
    H=$TMPDIR/home
    mkdir -p "$H/.config"
    run_adapter() {
      HOME="$H" bash ${omarchyPkg}/share/omarchy/migrations-nix/1780517689.sh >/dev/null
    }
    fail() { echo "$1"; shift; [ $# -eq 0 ] || cat "$@"; exit 1; }

    # 1. Fresh seed with both extensions on the Arch path:
    #    rewritten to the stable path, no duplicate line.
    printf '%s\n' '--ozone-platform=wayland' \
      "--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url,/usr/share/omarchy/default/chromium/extensions/yt-dlp" \
      > "$H/.config/chromium-flags.conf"
    run_adapter
    grep -qF -- "--load-extension=$EXT/copy-url,$EXT/yt-dlp" "$H/.config/chromium-flags.conf" \
      || fail "case1: Arch paths not rewritten" "$H/.config/chromium-flags.conf"
    [ "$(grep -c '^--load-extension=' "$H/.config/chromium-flags.conf")" = 1 ] \
      || fail "case1: duplicate load-extension line"

    # 2. copy-url only on the Arch path (the actual upstream
    #    migration case): yt-dlp appended, not just rewritten.
    printf '%s\n' "--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url" \
      > "$H/.config/chromium-flags.conf"
    run_adapter
    grep -qF -- "--load-extension=$EXT/copy-url,$EXT/yt-dlp" "$H/.config/chromium-flags.conf" \
      || fail "case2: yt-dlp not appended to a copy-url-only file" "$H/.config/chromium-flags.conf"

    # 3. A custom --load-extension line: both omarchy extensions
    #    appended onto it.
    printf '%s\n' '--load-extension=/home/u/exts/my-ext' > "$H/.config/brave-flags.conf"
    run_adapter
    grep -qF -- "--load-extension=/home/u/exts/my-ext,$EXT/copy-url,$EXT/yt-dlp" "$H/.config/brave-flags.conf" \
      || fail "case3: extensions not appended to a custom line" "$H/.config/brave-flags.conf"

    # 4. No extension line at all: the full line is appended.
    printf '%s\n' '--password-store=gnome-libsecret' > "$H/.config/google-chrome-flags.conf"
    run_adapter
    grep -qF -- "--load-extension=$EXT/copy-url,$EXT/yt-dlp" "$H/.config/google-chrome-flags.conf" \
      || fail "case4: full line not appended" "$H/.config/google-chrome-flags.conf"

    # 5. Idempotent: another run leaves every file byte-identical.
    find "$H/.config" -type f -exec md5sum {} + | sort > "$TMPDIR/before"
    run_adapter
    find "$H/.config" -type f -exec md5sum {} + | sort > "$TMPDIR/after"
    cmp -s "$TMPDIR/before" "$TMPDIR/after" \
      || fail "case5: adapter is not idempotent"

    touch $out
  ''
