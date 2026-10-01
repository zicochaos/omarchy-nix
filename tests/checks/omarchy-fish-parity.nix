# Bash/fish parity guard: every helper the pinned Quattro bash
# profile defines (aliases + functions in default/bash/aliases and
# default/bash/fns/*) must have a fish counterpart in the vendored
# profile (a vendor_functions.d file or a function defined in
# vendor_conf.d). A NEW upstream bash helper fails this check at
# bump time until fish gains it or it is consciously allowlisted
# in expectedMissing below (the fork-pin rationale is in the
# pkgs/omarchy-fish.nix header).
{
  self,
  pkgs,
  system,
  ...
}:
let
  fishPkg = self.packages.${system}.omarchy-fish;
  omarchyPkg = self.packages.${system}.omarchy;
  # Intentional omissions (bash helper -> why fish needs none):
  #   "..": omarchy-fish ships "..." and "...." but no "..", and
  #     fish itself has no builtin ".." — upstream fish-profile
  #     gap, not a port deviation. Remove from this list if
  #     omarchy-fish ever adds ...fish (the ".." function file).
  # The fork pin (PR omacom/omarchy-fish#7) carries the rest
  # of the Quattro helper set: a/c/cx/cy agent shortcuts, the
  # herdr family, and the ssh reconnect wrappers.
  expectedMissing = [ ".." ];
in
pkgs.runCommand "omarchy-fish-parity-check" { } ''
  set -euo pipefail
  fail() { echo "FAIL: $*" >&2; exit 1; }

  bashDir=${omarchyPkg}/share/omarchy/default/bash
  fishDir=${fishPkg}/share/fish

  # Bash contract: `alias X=`, `X() {`/`X () (` and `function X`
  # names from `aliases` and fns/* (leading whitespace tolerant —
  # a new upstream helper must not escape the guard by style).
  {
    grep -hoE '^[[:space:]]*alias[[:space:]]+[A-Za-z0-9_.-]+=' \
      "$bashDir/aliases" "$bashDir"/fns/* |
      sed -E 's/^[[:space:]]*alias[[:space:]]+//; s/=$//'
    grep -hoE '^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*\(\)' "$bashDir/aliases" "$bashDir"/fns/* |
      sed -E 's/^[[:space:]]*//; s/[[:space:]]*\(\)$//'
    grep -hoE '^[[:space:]]*function[[:space:]]+[A-Za-z0-9_.-]+' "$bashDir/aliases" "$bashDir"/fns/* |
      sed -E 's/^[[:space:]]*function[[:space:]]+//' || true
  } | LC_ALL=C sort -u > bash.txt

  # Fish contract: vendor_functions.d basenames + `function X`
  # definitions in vendor_conf.d (cd/zd live in conf.d/cd.fish).
  # dotglob so leading-dot function names (....fish) are seen.
  shopt -s dotglob
  {
    for f in "$fishDir"/vendor_functions.d/*.fish; do basename "$f" .fish; done
    grep -hoE '^function[[:space:]]+[A-Za-z0-9_.-]+' "$fishDir"/vendor_conf.d/*.fish |
      sed -E 's/^function[[:space:]]+//'
  } | LC_ALL=C sort -u > fish.txt
  shopt -u dotglob

  # Floors: an extraction that silently came back (nearly) empty would
  # make every comparison below pass. 55 bash helpers and 74 fish
  # functions as of 8b4eae6.
  [ "$(wc -l <bash.txt)" -ge 40 ] ||
    fail "only $(wc -l <bash.txt) bash helpers extracted (layout moved?)"
  [ "$(wc -l <fish.txt)" -ge 50 ] ||
    fail "only $(wc -l <fish.txt) fish functions extracted (layout moved?)"

  printf '%s\n' ${pkgs.lib.escapeShellArgs expectedMissing} | LC_ALL=C sort -u > expected.txt

  # Bash helpers without a fish counterpart, minus the allowlist.
  comm -23 bash.txt fish.txt > missing.txt
  comm -23 missing.txt expected.txt > unexpected.txt
  if [ -s unexpected.txt ]; then
    echo "bash helpers with no fish counterpart (add to fish or" >&2
    echo "allowlist in expectedMissing):" >&2
    cat unexpected.txt >&2
    fail "bash/fish parity broken"
  fi

  # Allowlist entries that no longer name a bash helper are stale
  # (the helper vanished upstream) — prune them at bump time.
  comm -23 expected.txt bash.txt > stale.txt
  if [ -s stale.txt ]; then
    echo "stale expectedMissing entries (no longer bash helpers):" >&2
    cat stale.txt >&2
    fail "prune expectedMissing"
  fi

  # Allowlist entries that meanwhile GAINED a fish counterpart
  # must leave the allowlist (fish caught up).
  comm -12 expected.txt fish.txt > covered.txt
  if [ -s covered.txt ]; then
    echo "expectedMissing entries now covered by fish (remove them):" >&2
    cat covered.txt >&2
    fail "prune expectedMissing"
  fi

  touch $out
''
