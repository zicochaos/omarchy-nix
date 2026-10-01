# omarchy update flow, run against fake system links: the reboot
# decision of the patched omarchy-update-restart (a boot-mode update
# moves only the system profile and must still offer the reboot; a
# switch only needs one for a new kernel) and the OMARCHY_PATH
# source-root check omarchy-update runs before taking sudo (the root
# must resolve into /nix/store and contain the entrypoint itself).
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
in
pkgs.runCommand "omarchy-update-flow-check" { } ''
  set -euo pipefail
  fail() { echo "FAIL: $*" >&2; exit 1; }
  bin=${omarchyPkg}/share/omarchy/bin
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"

  # --- reboot decision (omarchy-update-restart --reboot-only) -------
  # Generations are directories with a kernel link; booted, current and
  # profile point at them like /run/booted-system, /run/current-system
  # and /nix/var/nix/profiles/system.
  S=$TMPDIR/sys
  mkdir -p "$S/k1" "$S/k2" "$S/gen1" "$S/gen2" "$S/gen3"
  : >"$S/k1/bzImage"
  : >"$S/k2/bzImage"
  ln -s ../k1/bzImage "$S/gen1/kernel"
  ln -s ../k1/bzImage "$S/gen2/kernel" # new userland, same kernel
  ln -s ../k2/bzImage "$S/gen3/kernel" # new kernel
  restart() { # <booted> <current> <profile>
    ln -sfn "$S/$1" "$S/booted"
    ln -sfn "$S/$2" "$S/current"
    ln -sfn "$S/$3" "$S/profile"
    OMARCHY_UPDATE_UNATTENDED=1 \
      OMARCHY_NIX_BOOTED_SYSTEM=$S/booted \
      OMARCHY_NIX_CURRENT_SYSTEM=$S/current \
      OMARCHY_NIX_SYSTEM_PROFILE=$S/profile \
      "$bin/omarchy-update-restart" --reboot-only
  }

  # boot-mode update (the default): only the profile moved
  got=$(restart gen1 gen1 gen2)
  grep -q 'not active until you reboot' <<<"$got" ||
    fail "boot-mode update offered no reboot: $got"
  grep -q 'Reboot now to activate the new system generation' <<<"$got" ||
    fail "boot-mode reboot prompt missing: $got"
  grep -q "the migrations that just ran, uses the previous generation" <<<"$got" ||
    fail "boot-mode message must say the migrations ran on the old generation: $got"
  ! grep -qi 'kernel' <<<"$got" || fail "boot-mode message claims a kernel change: $got"
  # a boot-mode update after an earlier switch (current != booted)
  got=$(restart gen1 gen2 gen3)
  grep -q 'Reboot now to activate the new system generation' <<<"$got" ||
    fail "boot-mode update after a switch offered no reboot: $got"
  # switch with a new kernel
  got=$(restart gen1 gen3 gen3)
  grep -q 'Linux kernel has been updated' <<<"$got" || fail "switch + new kernel: $got"
  ! grep -q 'new system generation' <<<"$got" || fail "switch claims an inactive generation: $got"
  # switch with the same kernel, and no change at all: nothing to offer
  got=$(restart gen1 gen2 gen2)
  ! grep -qi 'reboot' <<<"$got" || fail "switch without a kernel change offered a reboot: $got"
  got=$(restart gen1 gen1 gen1)
  ! grep -qi 'reboot' <<<"$got" || fail "unchanged system offered a reboot: $got"
  # the flag upstream migrations set still applies
  mkdir -p "$HOME/.local/state/omarchy"
  : >"$HOME/.local/state/omarchy/reboot-required"
  got=$(restart gen1 gen1 gen1)
  grep -q 'Updates require reboot' <<<"$got" || fail "reboot-required flag ignored: $got"
  rm "$HOME/.local/state/omarchy/reboot-required"
  echo "reboot decision OK"

  # --- OMARCHY_PATH source root (omarchy-security-functions) --------
  root=${omarchyPkg}/share/omarchy
  src_root() { # <OMARCHY_PATH> <entrypoint>
    OMARCHY_PATH=$1 bash -c 'source "$1" && omarchy_security_require_source_root "$2"' \
      check "$bin/omarchy-security-functions" "$2" 2>/dev/null
  }
  src_root "$root" "$root/bin/omarchy-update" ||
    fail "the canonical store root was refused"
  # a directory of symlinks to the real scripts: the code that runs
  # would come from wherever the attacker points the other entries
  mkdir -p "$TMPDIR/fake/bin"
  ln -s "$root/bin/omarchy-update" "$TMPDIR/fake/bin/omarchy-update"
  if src_root "$TMPDIR/fake" "$TMPDIR/fake/bin/omarchy-update"; then
    fail "a root of symlinks to the real entrypoint was accepted"
  fi
  # a user-owned link to the store root (re-pointable after the check)
  ln -s "$root" "$TMPDIR/link"
  if src_root "$TMPDIR/link" "$TMPDIR/link/bin/omarchy-update"; then
    fail "a user-owned symlink to the store root was accepted"
  fi
  # a writable copy of the tree outside the store (canonical, and it
  # does contain the entrypoint — upstream accepts that as a dev
  # checkout; on NixOS the update code must come from the store)
  mkdir -p "$TMPDIR/copy/bin"
  cp "$root/bin/omarchy-update" "$root/bin/omarchy-security-functions" "$TMPDIR/copy/bin/"
  if src_root "$TMPDIR/copy" "$TMPDIR/copy/bin/omarchy-update"; then
    fail "a root outside /nix/store was accepted"
  fi
  # the entrypoint must belong to the selected root
  cp "$root/bin/omarchy-update" "$TMPDIR/copied-update"
  if src_root "$root" "$TMPDIR/copied-update"; then
    fail "an entrypoint outside the root was accepted"
  fi
  if src_root "relative/omarchy" "$root/bin/omarchy-update"; then
    fail "a relative OMARCHY_PATH was accepted"
  fi
  echo "source root OK"

  touch $out
''
