# Migration adapters (pkgs/migrations-nix/, class "adapter"): every
# packaged adapter runs the way omarchy-migrate runs it (bash -euo
# pipefail) against a fake HOME, with its source present and absent
# and with the edited config reached through a user symlink (writable:
# a dotfile repository; read-only: a Home Manager store link). A
# symlinked config is never replaced by a copy and a read-only one never
# fails the run. The adapter list is pinned: a new adapter fails this
# check until it has cases here.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  nvimPkg = self.packages.${system}.omarchy-nvim;
  # Records "<name> <args>" in $STUB_LOG; systemctl answers the OWE
  # probes (owed.service present when OWED_PRESENT=1, no graphical
  # session), omarchy-hw-match never matches.
  stub = pkgs.writeShellScript "adapter-stub" ''
    printf '%s %s\n' "''${0##*/}" "$*" >>"$STUB_LOG"
    case "''${0##*/} $*" in
      "systemctl --user cat owed.service") [[ ''${OWED_PRESENT:-0} == 1 ]] ;;
      "systemctl --user is-active --quiet graphical-session.target") exit 1 ;;
      "omarchy-hw-match "*) exit 1 ;;
      *) exit 0 ;;
    esac
  '';
in
pkgs.runCommand "omarchy-migration-adapters-check" { } ''
  set -euo pipefail
  fail() { echo "FAIL: $*" >&2; [[ ! -s $TMPDIR/run.log ]] || cat "$TMPDIR/run.log" >&2; exit 1; }
  A=${omarchyPkg}/share/omarchy/migrations-nix
  NVIM_SOURCE=${nvimPkg}/share/omarchy-nvim/config/lua/config/remote_clipboard.lua
  EXT=/run/current-system/sw/share/omarchy/default/chromium/extensions

  tested="1780517689.sh 1781587663.sh 1784401744.sh 1788996284.sh 1789764927.sh"
  [[ $(ls "$A" | sort | xargs) == "$tested" ]] ||
    fail "adapters changed ($(ls "$A" | xargs)); add their cases to this check"

  STUB=$TMPDIR/stub
  mkdir -p "$STUB"
  for s in omarchy-install-chromium-ytdlp omarchy-restart-tmux omarchy-hw-match gsettings \
    systemctl omarchy-hook-install; do
    ln -s ${stub} "$STUB/$s"
  done
  export STUB_LOG=$TMPDIR/stub.log
  # nvim adapters: with source = the omarchy-nvim package on PATH (as on
  # a NixOS system, where the profile links its bin/ only)
  WITH_NVIM=$STUB:${nvimPkg}/bin:$PATH
  NO_NVIM=$STUB:$PATH

  fresh() { H=$TMPDIR/home-$1; mkdir -p "$H/.config"; : >"$STUB_LOG"; }
  run() { # <adapter> <PATH> [VAR=value...]
    local adapter=$1 path=$2
    shift 2
    env HOME="$H" USER=tester PATH="$path" "$@" bash -euo pipefail "$A/$adapter" >"$TMPDIR/run.log" 2>&1 ||
      fail "$adapter exited non-zero"
  }
  # <link> <target-content> [ro]: a config reached through a symlink
  dotlink() {
    mkdir -p "$(dirname "$1")" "$TMPDIR/dot"
    local target
    target=$(mktemp "$TMPDIR/dot/target.XXXXXX")
    printf '%s\n' "$2" >"$target"
    [[ ''${3:-} != ro ]] || chmod 444 "$target"
    ln -s "$target" "$1"
  }
  is_link() { [[ -L $1 ]] || fail "$1 was replaced by a copy"; }

  : >"$TMPDIR/ro-probe"
  chmod 444 "$TMPDIR/ro-probe"
  [[ ! -w $TMPDIR/ro-probe ]] || fail "the sandbox user can write read-only files; the read-only cases cannot run"

  # --- 1780517689: yt-dlp extension in *-flags.conf -----------------
  fresh flags-absent
  run 1780517689.sh "$NO_NVIM"
  [[ -z $(find "$H/.config" -name '*-flags.conf') ]] || fail "1780517689 created a flags file"
  grep -q '^omarchy-install-chromium-ytdlp' "$STUB_LOG" || fail "1780517689 did not register the host"
  fresh flags-links
  dotlink "$H/.config/chromium-flags.conf" '--ozone-platform=wayland'
  dotlink "$H/.config/brave-flags.conf" '--ozone-platform=wayland' ro
  ro_before=$(cat "$H/.config/brave-flags.conf")
  run 1780517689.sh "$NO_NVIM"
  is_link "$H/.config/chromium-flags.conf"
  grep -qF -- "--load-extension=$EXT/copy-url,$EXT/yt-dlp" "$H/.config/chromium-flags.conf" ||
    fail "1780517689 did not edit through a writable symlink"
  is_link "$H/.config/brave-flags.conf"
  [[ $(cat "$H/.config/brave-flags.conf") == "$ro_before" ]] || fail "1780517689 changed a read-only target"
  grep -q 'Preserving read-only symlinked' "$TMPDIR/run.log" || fail "1780517689 skipped a read-only link silently"
  echo "1780517689 OK"

  # --- 1781587663: remote clipboard provider + options.lua + tmux ----
  setup_nvim() {
    mkdir -p "$H/.config/nvim/lua/config"
    printf '%s\n' 'vim.o.number = true' >"$H/.config/nvim/lua/config/options.lua"
    chmod 644 "$H/.config/nvim/lua/config/options.lua"
  }
  fresh nvim-present
  setup_nvim
  mkdir -p "$H/.config/tmux"
  printf '%s\n' 'set -g mouse on' >"$H/.config/tmux/tmux.conf"
  run 1781587663.sh "$WITH_NVIM"
  cmp -s "$NVIM_SOURCE" "$H/.config/nvim/lua/config/remote_clipboard.lua" ||
    fail "1781587663 did not install the packaged provider (source not found?)"
  opts=$H/.config/nvim/lua/config/options.lua
  [[ -f $opts && ! -L $opts && $(head -n1 "$opts") == 'require("config.remote_clipboard").setup()' ]] ||
    fail "1781587663 did not prepend the provider setup to options.lua"
  [[ $(stat -c %a "$opts") == 644 ]] || fail "1781587663 reset options.lua to mode $(stat -c %a "$opts")"
  grep -q ',\*:clipboard' "$H/.config/tmux/tmux.conf" || fail "1781587663 did not enable tmux clipboard forwarding"
  find "$H/.config" -type f | sort | xargs md5sum >"$TMPDIR/before"
  run 1781587663.sh "$WITH_NVIM"
  find "$H/.config" -type f | sort | xargs md5sum >"$TMPDIR/after"
  cmp -s "$TMPDIR/before" "$TMPDIR/after" || fail "1781587663 is not idempotent"

  fresh nvim-absent
  setup_nvim
  run 1781587663.sh "$NO_NVIM"
  grep -q 'source not found' "$TMPDIR/run.log" || fail "1781587663 without a source said nothing"
  [[ ! -e $H/.config/nvim/lua/config/remote_clipboard.lua ]] || fail "1781587663 installed a provider without a source"
  [[ $(cat "$H/.config/nvim/lua/config/options.lua") == 'vim.o.number = true' ]] ||
    fail "1781587663 edited options.lua without a source"

  fresh nvim-links
  dotlink "$H/.config/nvim/lua/config/options.lua" 'vim.o.number = true'
  dotlink "$H/.config/tmux/tmux.conf" 'set -g mouse on'
  run 1781587663.sh "$WITH_NVIM"
  is_link "$H/.config/nvim/lua/config/options.lua"
  [[ $(cat "$H/.config/nvim/lua/config/options.lua") == 'vim.o.number = true' ]] ||
    fail "1781587663 edited a symlink-managed options.lua"
  [[ ! -e $H/.config/nvim/lua/config/remote_clipboard.lua ]] ||
    fail "1781587663 installed into a symlink-managed config"
  grep -q 'Preserving symlink-managed Neovim config' "$TMPDIR/run.log" || fail "1781587663 skipped silently"
  is_link "$H/.config/tmux/tmux.conf"
  grep -q ',\*:clipboard' "$H/.config/tmux/tmux.conf" || fail "1781587663 did not append through a writable tmux link"

  fresh nvim-dir-link
  mkdir -p "$TMPDIR/dot/nvim-dir/lua/config"
  printf '%s\n' 'vim.o.number = true' >"$TMPDIR/dot/nvim-dir/lua/config/options.lua"
  ln -s "$TMPDIR/dot/nvim-dir" "$H/.config/nvim"
  dotlink "$H/.config/tmux/tmux.conf" 'set -g mouse on' ro
  run 1781587663.sh "$WITH_NVIM"
  is_link "$H/.config/nvim"
  [[ ! -e $TMPDIR/dot/nvim-dir/lua/config/remote_clipboard.lua ]] ||
    fail "1781587663 wrote into a symlinked nvim directory"
  [[ $(cat "$H/.config/tmux/tmux.conf") == 'set -g mouse on' ]] || fail "1781587663 changed a read-only tmux target"
  echo "1781587663 OK"

  # --- 1784401744: tmux bindings backfill ----------------------------
  old_tmux=$(printf '%s\n' 'set -g terminal-features[3] "xterm-kitty:extkeys"' '# Pane Controls' 'bind x kill-pane')
  check_tmux() {
    grep -qx 'set -ag terminal-features "xterm-kitty:extkeys"' "$1" &&
      grep -q 'M-S-Enter' "$1" || fail "1784401744 did not update $1"
  }
  fresh tmux-absent
  run 1784401744.sh "$NO_NVIM"
  ! grep -q '^omarchy-restart-tmux' "$STUB_LOG" || fail "1784401744 restarted tmux without a config"
  ! grep -q '^gsettings' "$STUB_LOG" || fail "1784401744 changed text scaling on other hardware"
  fresh tmux-present
  mkdir -p "$H/.config/tmux"
  printf '%s\n' "$old_tmux" >"$H/.config/tmux/tmux.conf"
  run 1784401744.sh "$NO_NVIM"
  check_tmux "$H/.config/tmux/tmux.conf"
  grep -q '^omarchy-restart-tmux' "$STUB_LOG" || fail "1784401744 did not restart tmux"
  fresh tmux-link
  dotlink "$H/.config/tmux/tmux.conf" "$old_tmux"
  run 1784401744.sh "$NO_NVIM"
  is_link "$H/.config/tmux/tmux.conf"
  check_tmux "$H/.config/tmux/tmux.conf"
  fresh tmux-ro-link
  dotlink "$H/.config/tmux/tmux.conf" "$old_tmux" ro
  run 1784401744.sh "$NO_NVIM"
  is_link "$H/.config/tmux/tmux.conf"
  [[ $(cat "$H/.config/tmux/tmux.conf") == "$old_tmux" ]] || fail "1784401744 changed a read-only target"
  grep -q 'Preserving read-only symlinked tmux config' "$TMPDIR/run.log" || fail "1784401744 skipped silently"
  echo "1784401744 OK"

  # --- 1788996284: remote clipboard provider repair ------------------
  # the pinned omarchy-nvim must not ship a provider this migration
  # treats as stale (it would refuse the package forever)
  ! grep -qF "$(sha256sum "$NVIM_SOURCE" | cut -d' ' -f1)" "$A/1788996284.sh" ||
    fail "the packaged omarchy-nvim provider is one 1788996284 replaces"
  provider_dir() { mkdir -p "$H/.config/nvim/lua/config"; echo "$H/.config/nvim/lua/config"; }
  fresh repair-none
  run 1788996284.sh "$WITH_NVIM"
  [[ ! -e $H/.config/nvim ]] || fail "1788996284 created a provider"
  fresh repair-current
  cp "$NVIM_SOURCE" "$(provider_dir)/remote_clipboard.lua"
  run 1788996284.sh "$WITH_NVIM"
  ! grep -q 'Preserving customized' "$TMPDIR/run.log" ||
    fail "1788996284 called the packaged provider customized (source not found?)"
  [[ -z $(find "$H/.config/nvim" -name '*.bak.*') ]] || fail "1788996284 replaced the current provider"
  fresh repair-custom
  echo '-- mine' >"$(provider_dir)/remote_clipboard.lua"
  for p in "$WITH_NVIM" "$NO_NVIM"; do
    run 1788996284.sh "$p"
    grep -q 'Preserving customized' "$TMPDIR/run.log" || fail "1788996284 did not preserve a customized provider"
    [[ $(cat "$H/.config/nvim/lua/config/remote_clipboard.lua") == '-- mine' ]] ||
      fail "1788996284 changed a customized provider"
  done
  fresh repair-link
  dotlink "$H/.config/nvim/lua/config/remote_clipboard.lua" '-- mine'
  run 1788996284.sh "$WITH_NVIM"
  is_link "$H/.config/nvim/lua/config/remote_clipboard.lua"
  grep -q 'Preserving symlink-managed' "$TMPDIR/run.log" || fail "1788996284 skipped a link silently"
  echo "1788996284 OK"

  # --- 1789764927: OWE user unit + theme hook ------------------------
  fresh owe-absent
  run 1789764927.sh "$NO_NVIM" OWED_PRESENT=0
  grep -q 'owed.service is not installed' "$TMPDIR/run.log" || fail "1789764927 without owe said nothing"
  ! grep -qE '^(omarchy-hook-install|systemctl --user enable)' "$STUB_LOG" ||
    fail "1789764927 enabled OWE without the unit"
  fresh owe-present
  run 1789764927.sh "$NO_NVIM" OWED_PRESENT=1
  grep -qx 'omarchy-hook-install theme-set /run/current-system/sw/share/owe/10-owe-sync' "$STUB_LOG" ||
    fail "1789764927 did not install the theme hook"
  grep -qx 'systemctl --user enable owed.service' "$STUB_LOG" || fail "1789764927 did not enable owed"
  ! grep -qx 'systemctl --user start owed.service' "$STUB_LOG" ||
    fail "1789764927 started owed without a graphical session"
  echo "1789764927 OK"

  touch $out
''
