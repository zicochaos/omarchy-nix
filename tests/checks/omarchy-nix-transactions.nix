# Transaction integrity for omarchy-nix-add / omarchy-nix-remove.
# Runs the PACKAGED scripts against stubbed
# sudo / nix / nixos-rebuild / fzf and asserts the acceptance
# criteria: parallel adds keep the union, add/remove collisions
# converge deterministically, one rebuild per batch, hash-checked
# rollback never reverts a newer mutation, audit logs persist, and
# the concurrency cases are repeated many times.
{
  self,
  pkgs,
  system,
  optLoaderGolden,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;

  # Passthrough sudo; SUDO_CHMOD_WINDOW=1 opens a write window on
  # the (0555) flake dir so tee/mv/rm can act as root would.
  # SUDO_LOG records every invocation's argv.
  stubSudo = pkgs.writeShellScript "stub-sudo" ''
    if [[ -n ''${SUDO_LOG:-} ]]; then
      printf '%s\n' "$*" >>"$SUDO_LOG"
    fi
    if [[ ''${SUDO_CHMOD_WINDOW:-0} == 1 ]]; then
      chmod -R u+w "$OMARCHY_NIX_FLAKE"
      if [[ -n ''${REBUILD_ROLLBACK_GATE:-} &&
            ''${REBUILD_LABEL:-} == rollback-first &&
            -e "$REBUILD_ROLLBACK_GATE/rebuild-failed" &&
            ! -e "$REBUILD_ROLLBACK_GATE/rollback-start" ]]; then
        : >"$REBUILD_ROLLBACK_GATE/rollback-start"
        while [[ ! -e "$REBUILD_ROLLBACK_GATE/rollback-release" ]]; do
          sleep 0.05
        done
      fi
      "$@"
      rc=$?
      chmod 555 "$OMARCHY_NIX_FLAKE"
      exit "$rc"
    fi
    exec "$@"
  '';

  # Counts invocations; optionally sabotages the JSON mid-rebuild
  # (a non-cooperating writer) and fails on demand.
  # FAKE_PROFILE_SWITCH=<gen> points OMARCHY_NIX_SYSTEM_PROFILE at a
  # new generation first, like a rebuild that installed the generation
  # and then failed in activation (exit 4).
  stubRebuild = pkgs.writeShellScript "stub-nixos-rebuild" ''
    echo x >> "''${COUNT_FILE:?}"
    if [[ -n ''${FAKE_PROFILE_SWITCH:-} ]]; then
      ln -sfn "$FAKE_PROFILE_SWITCH" "''${OMARCHY_NIX_SYSTEM_PROFILE:?}"
    fi
    if [[ -n ''${REBUILD_SERIAL_ROOT:-} ]]; then
      serial_root="$REBUILD_SERIAL_ROOT"
      mkdir -p "$serial_root"
      if ! mkdir "$serial_root/active" 2>/dev/null; then
        : >"$serial_root/overlap"
        exit 97
      fi
      label="''${REBUILD_LABEL:-unknown}"
      : >"$serial_root/entered-$label"
      cleanup() {
        rmdir "$serial_root/active" 2>/dev/null || true
      }
      trap cleanup EXIT
      if [[ -n ''${REBUILD_RELEASE_FILE:-} ]]; then
        while [[ ! -e "$REBUILD_RELEASE_FILE" ]]; do
          sleep 0.05
        done
      else
        sleep "''${REBUILD_SLEEP:-0}"
      fi
      : >"$serial_root/exited-$label"
    fi
    if [[ ''${REBUILD_SABOTAGE:-0} == 1 ]]; then
      j="$OMARCHY_NIX_FLAKE/omarchy-packages.json"
      ${pkgs.jq}/bin/jq '.packages = (((.packages // []) + ["sabotage-pkg"]) | unique)' "$j" >"$j.sabotage" \
        && mv "$j.sabotage" "$j"
    fi
    if [[ ''${FAKE_REBUILD_RC:-0} != 0 && -n ''${REBUILD_ROLLBACK_GATE:-} ]]; then
      : >"$REBUILD_ROLLBACK_GATE/rebuild-failed"
    fi
    exit "''${FAKE_REBUILD_RC:-0}"
  '';

  # Every raw nixpkgs attribute resolves (nix eval --quiet).
  # NIX_STUB_SLOW=1 makes `nix search` take 5s, to prove a slow
  # background index refresh does not hold the transaction lock.
  # `nix flake update` leaves a marker in REBUILD_SERIAL_ROOT (when
  # set), to prove omarchy update waits for the flake lock before it.
  stubNix = pkgs.writeShellScript "stub-nix" ''
    if [[ ''${1:-} == flake && ''${2:-} == update && -n ''${REBUILD_SERIAL_ROOT:-} ]]; then
      : >"$REBUILD_SERIAL_ROOT/flake-update-entered"
    fi
    if [[ ''${NIX_STUB_SLOW:-0} == 1 && ''${1:-} == search ]]; then
      if [[ -n ''${NIX_STUB_SLOW_MARKER:-} ]]; then
        # the session id (field 6 of /proc/<pid>/stat), to prove the
        # refresh is detached from the caller's terminal session
        read -r -a stat </proc/$$/stat
        printf '%s\n' "''${stat[5]}" >"$NIX_STUB_SLOW_MARKER"
      fi
      sleep 5
    fi
    exit 0
  '';

  # Emulates a two-pick multi-select: first two rows of stdin.
  stubFzf = pkgs.writeShellScript "stub-fzf" "head -2";
in
pkgs.runCommand "omarchy-nix-transactions-check"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.util-linux
      pkgs.git
    ];
  }
  ''
    set -euo pipefail

    export HOME=$TMPDIR/home
    export XDG_STATE_HOME=$TMPDIR/state
    export XDG_CACHE_HOME=$TMPDIR/cache
    export OMARCHY_PATH=${omarchyPkg}/share/omarchy
    mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

    STUB=$TMPDIR/bin
    mkdir -p "$STUB"
    ln -s ${stubSudo} "$STUB/sudo"
    ln -s ${stubRebuild} "$STUB/nixos-rebuild"
    ln -s ${stubNix} "$STUB/nix"
    ln -s ${stubFzf} "$STUB/fzf"
    export PATH="$STUB:${omarchyPkg}/share/omarchy/bin:$PATH"
    export COUNT_FILE=$TMPDIR/rebuild-count

    fail() { echo "FAIL: $*" >&2; exit 1; }
    new_flake() {
      export OMARCHY_NIX_FLAKE=$TMPDIR/flake-$1
      rm -rf "$OMARCHY_NIX_FLAKE"
      mkdir -p "$OMARCHY_NIX_FLAKE"
      echo '{ }' >"$OMARCHY_NIX_FLAKE/flake.nix"
    }
    json_pkgs() { jq -cS '.packages' "$OMARCHY_NIX_FLAKE/omarchy-packages.json"; }
    json_feats() { jq -cS '.features' "$OMARCHY_NIX_FLAKE/omarchy-packages.json"; }

    # --- (a) parallel adds keep the union (repeated) ----------------
    for round in $(seq 1 30); do
      new_flake "a$round"
      ids=()
      for i in $(seq 0 19); do ids+=("cpkg$round-$i"); done
      for id in "''${ids[@]}"; do omarchy-nix-add "$id" >/dev/null 2>&1 & done
      wait
      expect=$(printf '%s\n' "''${ids[@]}" | jq -R . | jq -sc 'unique')
      [[ $(json_pkgs) == "$expect" ]] || fail "case a round $round: union mismatch: $(json_pkgs)"
      [[ $(json_feats) == '[]' ]] || fail "case a round $round: unexpected features"
    done
    echo "case a (parallel union x30) OK"

    # --- (b) parallel add/remove with disjoint effects (repeated) ---
    # The flock fully serializes every
    # operation, so the result equals one of the two serial orders;
    # for disjoint effects both orders converge to the same state.
    for round in $(seq 1 10); do
      new_flake "b$round"
      printf '{"packages":["firefox"],"features":[]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
      omarchy-nix-add install.gaming.steam >/dev/null 2>&1 &
      omarchy-nix-remove firefox >/dev/null 2>&1 &
      wait
      jq -e . "$OMARCHY_NIX_FLAKE/omarchy-packages.json" >/dev/null || fail "case b round $round: invalid json"
      [[ $(json_feats) == '["steam"]' ]] || fail "case b round $round: steam feature lost"
      [[ $(json_pkgs) == '[]' ]] || fail "case b round $round: firefox not removed"
    done
    echo "case b (parallel add/remove x10) OK"

    # --- (c) failed rebuild restores the preimage -------------------
    new_flake c
    printf '{"packages":["mc"],"features":[]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    pre=$(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-packages.json" | cut -d' ' -f1)
    if FAKE_REBUILD_RC=1 omarchy-nix-add install.browser.firefox >/dev/null 2>&1; then
      fail "case c: failing rebuild must exit non-zero"
    fi
    [[ $(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-packages.json" | cut -d' ' -f1) == "$pre" ]] ||
      fail "case c: preimage not restored"
    grep -qr 'rollback: restored preimage' "$XDG_STATE_HOME/omarchy/nix-add/" ||
      fail "case c: audit log missing the restore note"
    echo "case c (rollback restores) OK"

    # --- (d) rollback never reverts a newer mutation ----------------
    new_flake d
    if FAKE_REBUILD_RC=1 REBUILD_SABOTAGE=1 omarchy-nix-add install.browser.firefox >/dev/null 2>&1; then
      fail "case d: failing rebuild must exit non-zero"
    fi
    [[ $(json_pkgs) == '["firefox","sabotage-pkg"]' ]] ||
      fail "case d: sabotaged json was reverted: $(json_pkgs)"
    grep -qr 'rollback: SKIPPED' "$XDG_STATE_HOME/omarchy/nix-add/" ||
      fail "case d: audit log missing the skip note"
    echo "case d (rollback skips newer mutation) OK"

    # --- (e) one rebuild per batch (add, search, remove) ------------
    new_flake e
    : >"$COUNT_FILE"
    omarchy-nix-add install.browser.firefox install.gaming.steam mc >/dev/null
    [[ $(json_pkgs) == '["firefox","mc"]' ]] || fail "case e: batch add pkgs"
    [[ $(json_feats) == '["steam"]' ]] || fail "case e: batch add features"
    [[ $(wc -l <"$COUNT_FILE") == 1 ]] || fail "case e: batch add must be 1 rebuild"

    export OMARCHY_NIX_INDEX_FILE=$TMPDIR/index-e.tsv
    printf 'aaa-pkg\tdesc a\t1.0\nzzz-pkg\tdesc z\t2.0\nmmm-pkg\tdesc m\t3.0\n' >"$OMARCHY_NIX_INDEX_FILE"
    omarchy-nix-search >/dev/null
    [[ $(json_pkgs) == '["aaa-pkg","firefox","mc","zzz-pkg"]' ]] || fail "case e: search picks installed"
    [[ $(wc -l <"$COUNT_FILE") == 2 ]] || fail "case e: search must be 1 rebuild"

    omarchy-nix-remove firefox mc >/dev/null
    [[ $(json_pkgs) == '["aaa-pkg","zzz-pkg"]' ]] || fail "case e: batch remove"
    [[ $(wc -l <"$COUNT_FILE") == 3 ]] || fail "case e: batch remove must be 1 rebuild"
    echo "case e (one rebuild per batch) OK"

    # --- (f) root-owned flake dir works via the sudo path -----------
    new_flake f
    chmod 555 "$OMARCHY_NIX_FLAKE"
    (exec 8<"$OMARCHY_NIX_FLAKE" && flock -n 8) ||
      fail "case f: read-only flake directory cannot be locked"
    SUDO_CHMOD_WINDOW=1 omarchy-nix-add install.browser.firefox >/dev/null
    [[ $(json_pkgs) == '["firefox"]' ]] || fail "case f: root-owned add"
    SUDO_CHMOD_WINDOW=1 omarchy-nix-remove firefox >/dev/null
    [[ $(json_pkgs) == '[]' ]] || fail "case f: root-owned remove"
    chmod 755 "$OMARCHY_NIX_FLAKE"
    echo "case f (root-owned flake) OK"

    # --- (g) dry-run writes json but never rebuilds -----------------
    new_flake g
    : >"$COUNT_FILE"
    dry_out=$(OMARCHY_NIX_UPDATE_DRY_RUN=1 omarchy-nix-add install.browser.firefox)
    [[ $(wc -l <"$COUNT_FILE") == 0 ]] || fail "case g: dry-run rebuilt"
    [[ $(json_pkgs) == '["firefox"]' ]] || fail "case g: dry-run did not write json"
    grep -q 'DRY-RUN:' <<<"$dry_out" || fail "case g: missing DRY-RUN marker"
    echo "case g (dry-run) OK"

    # --- (h) schema validation refuses to touch a bad json ----------
    new_flake h
    printf '{"packages":"oops"}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    pre=$(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-packages.json" | cut -d' ' -f1)
    if omarchy-nix-add install.browser.firefox >/dev/null 2>&1; then
      fail "case h: invalid schema must fail"
    fi
    [[ $(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-packages.json" | cut -d' ' -f1) == "$pre" ]] ||
      fail "case h: json modified despite invalid schema"
    echo "case h (schema validation) OK"

    # --- (i) no-op + git intent-to-add registration -----------------
    new_flake i
    git -C "$OMARCHY_NIX_FLAKE" init -q
    omarchy-nix-add install.browser.firefox >/dev/null
    git -C "$OMARCHY_NIX_FLAKE" ls-files | grep -q '^omarchy-packages.json$' ||
      fail "case i: json not registered with git"
    omarchy-nix-add install.browser.firefox >/dev/null
    git -C "$OMARCHY_NIX_FLAKE" ls-files | grep -q '^omarchy-packages.json$' ||
      fail "case i: registration lost on no-op"
    # a failing git add -N in a repository this user owns must not be
    # retried as root (root git would run the repo's fsmonitor/hooks
    # and leave a root-owned index behind)
    : >"$OMARCHY_NIX_FLAKE/.git/index.lock"
    SUDO_LOG=$TMPDIR/sudo-i.log omarchy-nix-add mc >/dev/null
    rm "$OMARCHY_NIX_FLAKE/.git/index.lock"
    if grep -q 'git' "$TMPDIR/sudo-i.log"; then
      fail "case i: git was retried through sudo in a user-owned repository: $(cat "$TMPDIR/sudo-i.log")"
    fi
    echo "case i (git registration + no-op) OK"

    # --- (j) background index refresh never holds the lock ----------
    new_flake j
    slow_marker=$TMPDIR/search-started
    rm -f "$slow_marker"
    NIX_STUB_SLOW=1 NIX_STUB_SLOW_MARKER="$slow_marker" \
      omarchy-nix-add install.browser.firefox >/dev/null
    for attempt in $(seq 1 100); do
      [[ -e $slow_marker ]] && break
      sleep 0.05
    done
    [[ -e $slow_marker ]] || fail "case j: slow background refresh did not start"
    exec 8<"$OMARCHY_NIX_FLAKE"
    flock -w 3 8 ||
      fail "case j: background index refresh still holds the transaction lock"
    exec 8<&-
    # its own session: closing the floating terminal (SIGHUP to the
    # terminal's session) must not kill the refresh
    for attempt in $(seq 1 100); do
      [[ -s $slow_marker ]] && break
      sleep 0.05
    done
    read -r -a own_stat </proc/$$/stat
    [[ $(cat "$slow_marker") != "''${own_stat[5]}" ]] ||
      fail "case j: the background refresh runs in the caller's session"
    echo "case j (no lock leak to background, detached session) OK"

    # --- (k) remove picker (fzf --multi, no args) -------------------
    new_flake k
    : >"$COUNT_FILE"
    printf '{"packages":["aaa-pkg","zzz-pkg"],"features":["steam"]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    omarchy-nix-remove >/dev/null
    [[ $(json_pkgs) == '[]' ]] || fail "case k: picker remove pkgs: $(json_pkgs)"
    [[ $(json_feats) == '["steam"]' ]] || fail "case k: picker remove must keep unpicked features"
    [[ $(wc -l <"$COUNT_FILE") == 1 ]] || fail "case k: picker remove must be 1 rebuild"
    echo "case k (remove picker multi) OK"

    # --- (l) features absent from the catalog stay removable --------
    new_flake l
    printf '{"packages":[],"features":["ghost-feature"]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    omarchy-nix-remove ghost-feature >/dev/null
    [[ $(json_feats) == '[]' ]] || fail "case l: uncataloged feature not removable"
    echo "case l (uncataloged feature remove) OK"

    # --- (m) separate users/state dirs still serialize rebuilds ----
    new_flake m
    serial_root=$TMPDIR/serial-m
    mkdir -p "$serial_root"
    export REBUILD_SERIAL_ROOT=$serial_root
    export REBUILD_RELEASE_FILE=$serial_root/release
    XDG_STATE_HOME=$TMPDIR/state-m1 REBUILD_LABEL=first \
      omarchy-nix-add install.browser.firefox \
      >"$serial_root/first.log" 2>&1 &
    first_pid=$!
    for attempt in $(seq 1 100); do
      [[ -e $serial_root/entered-first ]] && break
      sleep 0.05
    done
    if [[ ! -e $serial_root/entered-first ]]; then
      : >"$REBUILD_RELEASE_FILE"
      kill "$first_pid" 2>/dev/null || true
      wait "$first_pid" 2>/dev/null || true
      fail "case m: first rebuild did not start"
    fi
    XDG_STATE_HOME=$TMPDIR/state-m2 REBUILD_LABEL=second \
      omarchy-nix-add mc \
      >"$serial_root/second.log" 2>&1 &
    second_pid=$!
    sleep 0.2
    if [[ -e $serial_root/entered-second ]]; then
      : >"$REBUILD_RELEASE_FILE"
      wait "$first_pid" 2>/dev/null || true
      wait "$second_pid" 2>/dev/null || true
      fail "case m: different XDG_STATE_HOME values did not serialize"
    fi
    : >"$REBUILD_RELEASE_FILE"
    if ! wait "$first_pid"; then
      fail "case m: first serialized rebuild failed"
    fi
    if ! wait "$second_pid"; then
      fail "case m: second serialized rebuild failed"
    fi
    [[ ! -e $serial_root/overlap ]] || fail "case m: rebuilds overlapped"
    [[ $(json_pkgs) == '["firefox","mc"]' ]] ||
      fail "case m: serialized operations lost a package: $(json_pkgs)"
    unset REBUILD_SERIAL_ROOT REBUILD_RELEASE_FILE
    echo "case m (cross-state rebuild serialization) OK"

    # --- (n) the same lock remains held through rollback -----------
    new_flake n
    printf '{"packages":[],"features":[]}' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    chmod 555 "$OMARCHY_NIX_FLAKE"
    serial_root=$TMPDIR/serial-n
    mkdir -p "$serial_root"
    export REBUILD_SERIAL_ROOT=$serial_root
    export REBUILD_RELEASE_FILE=$serial_root/release
    XDG_STATE_HOME=$TMPDIR/state-n1 REBUILD_LABEL=rollback-first \
      REBUILD_ROLLBACK_GATE=$serial_root SUDO_CHMOD_WINDOW=1 \
      FAKE_REBUILD_RC=1 omarchy-nix-add install.browser.firefox \
      >"$serial_root/first.log" 2>&1 &
    first_pid=$!
    for attempt in $(seq 1 100); do
      [[ -e $serial_root/entered-rollback-first ]] && break
      sleep 0.05
    done
    if [[ ! -e $serial_root/entered-rollback-first ]]; then
      : >"$REBUILD_RELEASE_FILE"
      kill "$first_pid" 2>/dev/null || true
      wait "$first_pid" 2>/dev/null || true
      chmod 755 "$OMARCHY_NIX_FLAKE"
      fail "case n: failing rebuild did not start"
    fi
    XDG_STATE_HOME=$TMPDIR/state-n2 REBUILD_LABEL=rollback-second \
      SUDO_CHMOD_WINDOW=1 omarchy-nix-add mc \
      >"$serial_root/second.log" 2>&1 &
    second_pid=$!
    sleep 0.2
    if [[ -e $serial_root/entered-rollback-second ]]; then
      : >"$REBUILD_RELEASE_FILE"
      : >"$serial_root/rollback-release"
      wait "$first_pid" 2>/dev/null || true
      wait "$second_pid" 2>/dev/null || true
      chmod 755 "$OMARCHY_NIX_FLAKE"
      fail "case n: second rebuild entered before rollback"
    fi
    : >"$REBUILD_RELEASE_FILE"
    for attempt in $(seq 1 100); do
      [[ -e $serial_root/rollback-start ]] && break
      sleep 0.05
    done
    [[ -e $serial_root/rollback-start ]] || {
      : >"$serial_root/rollback-release"
      wait "$first_pid" 2>/dev/null || true
      wait "$second_pid" 2>/dev/null || true
      chmod 755 "$OMARCHY_NIX_FLAKE"
      fail "case n: rollback did not start"
    }
    [[ ! -e $serial_root/entered-rollback-second ]] ||
      fail "case n: second rebuild entered during rollback"
    : >"$serial_root/rollback-release"
    if wait "$first_pid"; then
      chmod 755 "$OMARCHY_NIX_FLAKE"
      fail "case n: failing rebuild unexpectedly succeeded"
    fi
    if ! wait "$second_pid"; then
      chmod 755 "$OMARCHY_NIX_FLAKE"
      fail "case n: second rebuild after rollback failed"
    fi
    chmod 755 "$OMARCHY_NIX_FLAKE"
    [[ ! -e $serial_root/overlap ]] || fail "case n: rebuilds overlapped"
    [[ $(json_pkgs) == '["mc"]' ]] ||
      fail "case n: rollback lost the later mutation: $(json_pkgs)"
    grep -q 'rollback: restored preimage' \
      "$TMPDIR/state-n1/omarchy/nix-add/"*.log ||
      fail "case n: rollback audit entry missing"
    unset REBUILD_SERIAL_ROOT REBUILD_RELEASE_FILE
    echo "case n (cross-state rollback serialization) OK"

    # --- (p) omarchy update takes the same flake lock ---------------
    # omarchy-update-system-pkgs runs nix flake update + nixos-rebuild
    # on the flake add/remove mutate: it must wait for an add holding
    # the lock through its rebuild instead of interleaving with it.
    new_flake p
    serial_root=$TMPDIR/serial-p
    mkdir -p "$serial_root"
    export REBUILD_SERIAL_ROOT=$serial_root
    export REBUILD_RELEASE_FILE=$serial_root/release
    REBUILD_LABEL=add omarchy-nix-add install.browser.firefox \
      >"$serial_root/add.log" 2>&1 &
    add_pid=$!
    for attempt in $(seq 1 100); do
      [[ -e $serial_root/entered-add ]] && break
      sleep 0.05
    done
    if [[ ! -e $serial_root/entered-add ]]; then
      : >"$REBUILD_RELEASE_FILE"
      kill "$add_pid" 2>/dev/null || true
      wait "$add_pid" 2>/dev/null || true
      fail "case p: the add's rebuild did not start"
    fi
    REBUILD_LABEL=update omarchy-update-system-pkgs \
      >"$serial_root/update.log" 2>&1 &
    update_pid=$!
    sleep 0.3
    if [[ -e $serial_root/flake-update-entered || -e $serial_root/entered-update ]]; then
      : >"$REBUILD_RELEASE_FILE"
      wait "$add_pid" 2>/dev/null || true
      wait "$update_pid" 2>/dev/null || true
      fail "case p: omarchy update ran its flake update/rebuild while an add held the flake lock"
    fi
    : >"$REBUILD_RELEASE_FILE"
    wait "$add_pid" || fail "case p: add failed: $(cat "$serial_root/add.log")"
    wait "$update_pid" || fail "case p: update failed: $(cat "$serial_root/update.log")"
    [[ ! -e $serial_root/overlap ]] || fail "case p: rebuilds overlapped"
    [[ -e $serial_root/entered-update && -e $serial_root/flake-update-entered ]] ||
      fail "case p: update never ran after the lock was released"
    grep -q 'Waiting for another install/remove/update' "$serial_root/update.log" ||
      fail "case p: the waiting update said nothing: $(cat "$serial_root/update.log")"
    unset REBUILD_SERIAL_ROOT REBUILD_RELEASE_FILE
    echo "case p (omarchy update shares the flake lock) OK"

    # --- (q) a failure after the profile switched keeps the JSON ----
    # nixos-rebuild switch exits 4 when activation finished with failed
    # units — after the new generation is installed and running. A
    # rollback would leave the JSON saying "not installed" while the
    # system has the package, and the next rebuild would drop it.
    new_flake q
    P=$TMPDIR/profiles-q
    mkdir -p "$P/gen1" "$P/gen2"
    ln -s "$P/gen1" "$P/system"
    export OMARCHY_NIX_SYSTEM_PROFILE=$P/system
    printf '{"packages":["mc"],"features":[]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    if FAKE_REBUILD_RC=4 FAKE_PROFILE_SWITCH=$P/gen2 \
      XDG_STATE_HOME=$TMPDIR/state-q omarchy-nix-add install.browser.firefox >"$TMPDIR/q.log" 2>&1; then
      fail "case q: a failed activation must exit non-zero"
    fi
    [[ $(json_pkgs) == '["firefox","mc"]' ]] ||
      fail "case q: JSON rolled back although the system profile switched: $(json_pkgs)"
    grep -q 'Installed, but activation reported failures' "$TMPDIR/q.log" ||
      fail "case q: no installed-with-failures message: $(cat "$TMPDIR/q.log")"
    grep -qr 'after the system profile switched' "$TMPDIR/state-q/omarchy/nix-add/" ||
      fail "case q: audit log missing the kept-JSON note"
    # the profile did not move: the failure still rolls back
    if FAKE_REBUILD_RC=1 omarchy-nix-add install.gaming.steam >/dev/null 2>&1; then
      fail "case q: failing rebuild must exit non-zero"
    fi
    [[ $(json_feats) == '[]' ]] || fail "case q: unchanged profile, but no rollback: $(json_feats)"
    unset OMARCHY_NIX_SYSTEM_PROFILE
    echo "case q (failed activation after the switch keeps the JSON) OK"

    # --- (r) temp files: unique, mode-preserving -------------------
    # The JSON's temp used to be "$json.tmp.$$": a symlink planted at
    # that name was followed (write into its target) and then renamed
    # over the JSON. Start an add with a known PID (exec keeps it) and
    # plant the symlink before it writes.
    new_flake r
    printf '{"packages":[],"features":[]}\n' >"$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    chmod 644 "$OMARCHY_NIX_FLAKE/omarchy-packages.json"
    echo victim >"$TMPDIR/victim-r"
    mkfifo "$TMPDIR/go-r"
    bash -c 'echo $$ >"$1"; read -r _ <"$2"; exec omarchy-nix-add mc' \
      plant "$TMPDIR/pid-r" "$TMPDIR/go-r" >/dev/null 2>&1 &
    plant_pid=$!
    for attempt in $(seq 1 100); do
      [[ -s $TMPDIR/pid-r ]] && break
      sleep 0.05
    done
    ln -s "$TMPDIR/victim-r" "$OMARCHY_NIX_FLAKE/omarchy-packages.json.tmp.$(cat "$TMPDIR/pid-r")"
    echo go >"$TMPDIR/go-r"
    wait "$plant_pid" || fail "case r: add failed"
    [[ $(cat "$TMPDIR/victim-r") == victim ]] || fail "case r: the JSON write followed a planted symlink"
    [[ -f $OMARCHY_NIX_FLAKE/omarchy-packages.json && ! -L $OMARCHY_NIX_FLAKE/omarchy-packages.json ]] ||
      fail "case r: the JSON was replaced by a planted symlink"
    [[ $(json_pkgs) == '["mc"]' ]] || fail "case r: add lost: $(json_pkgs)"
    [[ $(stat -c %a "$OMARCHY_NIX_FLAKE/omarchy-packages.json") == 644 ]] ||
      fail "case r: JSON mode changed to $(stat -c %a "$OMARCHY_NIX_FLAKE/omarchy-packages.json")"
    # the same for the search index temp ("$INDEX.tmp" was fixed)
    echo victim >"$TMPDIR/victim-r2"
    ln -s "$TMPDIR/victim-r2" "$TMPDIR/index-r.tsv.tmp"
    OMARCHY_NIX_INDEX_FILE=$TMPDIR/index-r.tsv omarchy-nix-search --refresh >/dev/null 2>&1 ||
      fail "case r: index refresh failed"
    [[ $(cat "$TMPDIR/victim-r2") == victim ]] || fail "case r: the index build followed a planted symlink"
    [[ -f $TMPDIR/index-r.tsv && ! -L $TMPDIR/index-r.tsv ]] || fail "case r: index replaced by a symlink"
    leftovers=$(find "$OMARCHY_NIX_FLAKE" "$TMPDIR" -maxdepth 1 -name '*.tmp.*' ! -name "omarchy-packages.json.tmp.$(cat "$TMPDIR/pid-r")")
    [[ -z $leftovers ]] || fail "case r: temp files left behind: $leftovers"
    echo "case r (unique mode-preserving temp files) OK"

    # --- (o) NixOS options: opt: adds, mixed batches, validation,
    # the loader golden, classification, remove and rollback ----
    new_flake o
    : >"$COUNT_FILE"
    omarchy-nix-add opt:services.tailscale.enable=true >/dev/null
    jq -e '. == {"services.tailscale.enable":true}' \
      "$OMARCHY_NIX_FLAKE/omarchy-options.json" >/dev/null ||
      fail "case o: bool option not written: $(cat "$OMARCHY_NIX_FLAKE/omarchy-options.json")"
    [[ ! -f $OMARCHY_NIX_FLAKE/omarchy-packages.json ]] ||
      fail "case o: options-only add created a packages json"
    cmp -s ${optLoaderGolden} "$OMARCHY_NIX_FLAKE/omarchy-options.nix" ||
      fail "case o: generated loader differs from the golden template"
    omarchy-nix-add mc opt:services.tailscale.extraSetFlags='["--foo"]' >/dev/null
    jq -e '. == {"services.tailscale.enable":true,"services.tailscale.extraSetFlags":["--foo"]}' \
      "$OMARCHY_NIX_FLAKE/omarchy-options.json" >/dev/null ||
      fail "case o: list option not written"
    [[ $(json_pkgs) == '["mc"]' ]] ||
      fail "case o: mixed batch lost the package half"
    [[ $(wc -l <"$COUNT_FILE") == 2 ]] ||
      fail "case o: options must batch into one rebuild per call"

    # invalid JSON value: refused before any write/rebuild
    pre=$(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-options.json" | cut -d' ' -f1)
    if omarchy-nix-add opt:services.x.y=notjson >/dev/null 2>&1; then
      fail "case o: non-JSON value accepted"
    fi
    # malformed ids: no value / no dotted path
    if omarchy-nix-add opt:services.x.y >/dev/null 2>&1; then
      fail "case o: id without =value accepted"
    fi
    if omarchy-nix-add opt:nodot=true >/dev/null 2>&1; then
      fail "case o: undotted path accepted"
    fi
    # an empty value and a value stream are refused like invalid JSON:
    # before the lock (held here by another process — a refusal after
    # the lock would block) and with the usual message, not a raw jq
    # error from --argjson
    exec 8<"$OMARCHY_NIX_FLAKE"
    flock 8
    for v in "" "1 2"; do
      rc=0
      timeout 10 omarchy-nix-add "opt:services.x.y=$v" >"$TMPDIR/o-val.log" 2>&1 || rc=$?
      ((rc == 1)) || fail "case o: value '$v' exited $rc (124 = waited for the lock): $(cat "$TMPDIR/o-val.log")"
      grep -q 'Nothing was changed' "$TMPDIR/o-val.log" ||
        fail "case o: value '$v' refused without the usual message: $(cat "$TMPDIR/o-val.log")"
      ! grep -q 'jq: ' "$TMPDIR/o-val.log" || fail "case o: raw jq error for value '$v'"
    done
    exec 8<&-
    [[ $(sha256sum "$OMARCHY_NIX_FLAKE/omarchy-options.json" | cut -d' ' -f1) == "$pre" ]] ||
      fail "case o: options json modified by a refused id"
    # option picks through the search picker (two rows, stub fzf takes
    # both): the prompt hands add exactly the value — its text goes to
    # stderr — a stream typed at the free-form prompt becomes a string
    # (like bare words), never `1\n2`, and a boolean comes from select
    export OMARCHY_NIX_OPTS_INDEX_FILE=$TMPDIR/opts-o.tsv
    printf '%s\n' $'services.x.count\tsigned integer\t\t\tcount' \
      $'services.x.enable\tboolean\tfalse\t\tswitch' >"$OMARCHY_NIX_OPTS_INDEX_FILE"
    : >"$TMPDIR/empty-index-o.tsv"
    printf '1 2\n1\n' | OMARCHY_NIX_INDEX_FILE=$TMPDIR/empty-index-o.tsv omarchy-nix-search >"$TMPDIR/o-search.log" 2>&1 ||
      fail "case o: search option picks failed: $(cat "$TMPDIR/o-search.log")"
    jq -e '."services.x.count" == "1 2" and ."services.x.enable" == true' \
      "$OMARCHY_NIX_FLAKE/omarchy-options.json" >/dev/null ||
      fail "case o: search did not pass the picked values: $(cat "$OMARCHY_NIX_FLAKE/omarchy-options.json")"
    omarchy-nix-remove services.x.count services.x.enable >/dev/null
    unset OMARCHY_NIX_OPTS_INDEX_FILE

    # remove by bare path (classified by omarchy-options.json
    # membership), leaving packages untouched
    omarchy-nix-remove services.tailscale.enable >/dev/null
    jq -e 'has("services.tailscale.enable") | not' \
      "$OMARCHY_NIX_FLAKE/omarchy-options.json" >/dev/null ||
      fail "case o: option not removed"
    [[ $(json_pkgs) == '["mc"]' ]] ||
      fail "case o: option remove touched packages"

    # failed rebuild rolls the options pair back as a unit
    if FAKE_REBUILD_RC=1 omarchy-nix-add opt:virtualisation.docker.enable=true >/dev/null 2>&1; then
      fail "case o: failing rebuild must exit non-zero"
    fi
    jq -e 'has("virtualisation.docker.enable") | not' \
      "$OMARCHY_NIX_FLAKE/omarchy-options.json" >/dev/null ||
      fail "case o: failed rebuild left the new option behind"
    grep -qr 'rollback: restored options pair' "$XDG_STATE_HOME/omarchy/nix-add/" ||
      fail "case o: audit log missing the options restore note"
    echo "case o (NixOS options add/remove) OK"

    # --- audit logs exist and are complete for a successful op ------
    logf=$(grep -rl 'result: rebuild ok' "$XDG_STATE_HOME/omarchy/nix-add/" | head -1 || true)
    [[ -n $logf ]] || fail "no successful audit log found"
    for k in 'command:' 'ids:' 'pre-hash:' 'post-hash:' 'result:'; do
      grep -q "$k" "$logf" || fail "audit log missing field: $k"
    done
    echo "audit log completeness OK"

    touch $out
  ''
