# Package contract for the vendored Fish profile:
# every installed .fish file parses, the vendor dirs are populated
# (including leading-dot functions), fzf.fish v10.3 is bundled, the
# Quattro bash-parity helpers ship (fork pin carrying PR
# omacom/omarchy-fish#7), try.fish carries the lazy `try init`
# integration, and no active file references Arch-only paths or
# pacman.
{
  self,
  pkgs,
  system,
  ...
}:
let
  fishPkg = self.packages.${system}.omarchy-fish;
in
pkgs.runCommand "omarchy-fish-package-check" { nativeBuildInputs = [ pkgs.fish ]; } ''
  set -euo pipefail
  fail() { echo "FAIL: $*" >&2; exit 1; }

  cd ${fishPkg}

  # Every installed fish file parses (82 files as of 8b4eae6; the floor
  # keeps an empty tree from passing the loop vacuously).
  find share/fish -name '*.fish' -print0 >"$TMPDIR/fish-files"
  parsed=0
  while IFS= read -r -d "" f; do
    fish -n "$f" || fail "fish -n: $f"
    parsed=$((parsed + 1))
  done <"$TMPDIR/fish-files"
  [ "$parsed" -ge 60 ] || fail "only $parsed fish files found"

  # Vendor dirs populated, including leading-dot functions
  # (proves the dotglob copy in the package).
  for d in vendor_conf.d vendor_functions.d vendor_completions.d; do
    [ -n "$(ls -A "share/fish/$d")" ] || fail "empty share/fish/$d"
  done
  [ -e share/fish/vendor_functions.d/....fish ] || fail "missing ....fish"
  [ -e share/fish/vendor_functions.d/.....fish ] || fail "missing .....fish"

  # fzf.fish v10.3 bundled (name unique to fzf.fish — omarchy-fish
  # ships its own _fzf_search_history.fish, so it cannot be used).
  [ -e share/fish/vendor_functions.d/_fzf_search_git_log.fish ] ||
    fail "fzf.fish functions not bundled"

  # Quattro bash-parity helpers (PR omacom/omarchy-fish#7,
  # currently via the fork pin — see pkgs/omarchy-fish.nix).
  for fn in a h cy mup rsw lsw dsw tds \
    hdl hds hdlm hsl _herdr_ratio _herdr_split \
    ssh _ssh_disarm _ssh_interactive; do
    [ -e "share/fish/vendor_functions.d/$fn.fish" ] ||
      fail "missing $fn.fish (bash-parity helper)"
  done

  # Agent-shortcut drift guard: the helper NAMES above are also
  # covered by omarchy-fish-parity, but a flag change upstream
  # (e.g. cx bypassPermissions -> auto on 2026-08-15) keeps the
  # name while changing behavior — pin the current flags.
  grep -q 'omarchy-agent --inline' share/fish/vendor_functions.d/a.fish ||
    fail "a.fish lost the omarchy-agent --inline invocation"
  grep -q -- '--auto' share/fish/vendor_functions.d/c.fish ||
    fail "c.fish lost opencode --auto"
  grep -q -- '--permission-mode auto' share/fish/vendor_functions.d/cx.fish ||
    fail "cx.fish no longer uses --permission-mode auto"
  grep -q -- '--approve-for-me' share/fish/vendor_functions.d/cy.fish ||
    fail "cy.fish no longer uses codex --approve-for-me"
  grep -q 'SHELL=(command -v fish)' share/fish/vendor_functions.d/ff.fish ||
    fail "ff.fish lost the fish SHELL pin for the fzf preview"

  # try.fish ships again: PR #7 replaced the v1.5.0 version
  # (/usr/bin/try, /usr/bin/env ruby, pacman hint — B24) with a
  # lazy `try init` integration. Presence + content assertion.
  [ -e share/fish/vendor_functions.d/try.fish ] ||
    fail "try.fish missing (lazy try-init integration must ship)"
  grep -q 'command try init' share/fish/vendor_functions.d/try.fish ||
    fail "try.fish lacks the try init integration"

  # The omarchy completion implements the `# omarchy:args=`
  # contract (drives `omarchy <cmd>` argument completion).
  grep -q 'omarchy:args=' share/fish/vendor_completions.d/omarchy.fish ||
    fail "omarchy completion lacks the omarchy:args= contract"

  # No active file depends on Arch-only paths or pacman.
  # /usr/bin is forbidden wholesale on purpose: any reference is
  # a hard-coded path outside the nix store (v1.5.0 try.fish's
  # /usr/bin/env ruby was exactly the violation class).
  if grep -rn -E '/usr/bin|/usr/share/omarchy-fish|pacman' share/fish bin; then
    fail "Arch-only path/pacman reference in active fish files"
  fi

  # Docs + licenses.
  for f in LICENSE README.md LICENSE.fzf.fish README.fzf.fish.md; do
    [ -e "share/omarchy-fish/$f" ] || fail "missing share/omarchy-fish/$f"
  done
  [ -d share/omarchy-fish/templates ] || fail "missing templates dir"

  touch $out
''
