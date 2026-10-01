# One OMARCHY_NIX_FLAKE resolver for every omarchy-nix command.
# Asserts all consumers accept the same two explicit
# forms (flake dir / flake.nix file), canonicalize symlinks and
# whitespace, fail CLOSED on an invalid explicit value (never fall
# back to another checkout), and that presence checks observe the
# same JSON that add/remove mutate.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  # Marker-aware nix stub: answers the resolver's foreign-library
  # probe (nix eval --json <flake>#nixosConfigurations --apply
  # builtins.attrNames) with this host's name when <flake>/.consumer
  # exists and another host's otherwise; everything else exits 0 so
  # nothing real is rebuilt. Every argv lands in $NIX_ARGV_LOG.
  stubNix = pkgs.writeShellScript "stub-nix" ''
    printf '%s\n' "$*" >>"''${NIX_ARGV_LOG:-/dev/null}"
    for arg in "$@"; do
      case "$arg" in
        *#nixosConfigurations)
          flake=''${arg%%#*}
          if [ -f "$flake/.consumer" ]; then
            printf '["other-host","%s"]\n' "$(uname -n)"
          else
            echo '["demo","example"]'
          fi
          exit 0
          ;;
      esac
    done
    exit 0
  '';
  stubFzf = pkgs.writeShellScript "stub-fzf" "head -2";
in
pkgs.runCommand "omarchy-flake-resolver-check"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.util-linux
    ];
  }
  ''
    set -euo pipefail

    export HOME=$TMPDIR/home
    export XDG_STATE_HOME=$TMPDIR/state
    export XDG_CACHE_HOME=$TMPDIR/cache
    export OMARCHY_PATH=${omarchyPkg}/share/omarchy
    # never rebuild / refresh anything real in this check
    export OMARCHY_NIX_UPDATE_DRY_RUN=1
    export OMARCHY_NIX_SKIP_FLAKE_UPDATE=1
    export NIX_ARGV_LOG=$TMPDIR/nix-argv.log
    mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

    STUB=$TMPDIR/bin
    mkdir -p "$STUB"
    ln -s ${stubNix} "$STUB/nix"
    ln -s ${stubFzf} "$STUB/fzf"
    export PATH="$STUB:${omarchyPkg}/share/omarchy/bin:$PATH"

    fail() { echo "FAIL: $*" >&2; exit 1; }
    mkrepo() { mkdir -p "$1" && echo '{ }' >"$1/flake.nix"; }
    # A consumer flake (its nixosConfigurations have this host):
    # marker file the nix stub answers "host" for.
    mkconsumer() { mkrepo "$1" && touch "$1/.consumer"; }
    canon() { cd -- "$1" && pwd -P; }

    # --- no explicit value, no candidates: update skips gracefully,
    #     add refuses ------------------------------------------------
    # (relies on the build sandbox having no /etc/nixos/flake.nix —
    # true for sandboxed runCommand)
    got=$(omarchy-update-system-pkgs)
    grep -q 'no consumer flake found' <<<"$got" || fail "update: expected graceful skip, got: $got"
    if omarchy-nix-add install.browser.firefox >/dev/null 2>&1; then
      fail "add without any flake must fail"
    fi
    echo "no-flake handling OK"

    # --- candidates probing (no explicit value) ---------------------
    mkconsumer "$HOME/omarchy-nix"
    omarchy-nix-add install.browser.firefox >/dev/null
    [[ -f $HOME/omarchy-nix/omarchy-packages.json ]] || fail "candidate repo not used"
    omarchy-pkg-present firefox || fail "pkg-present must observe the candidate JSON"
    echo "candidates OK"

    # --- dir form ---------------------------------------------------
    mkrepo "$TMPDIR/repo-dir"
    OMARCHY_NIX_FLAKE=$TMPDIR/repo-dir omarchy-nix-add install.browser.firefox >/dev/null
    [[ -f $TMPDIR/repo-dir/omarchy-packages.json ]] || fail "dir form"
    echo "dir form OK"

    # --- flake.nix file form resolves to its directory --------------
    mkrepo "$TMPDIR/repo-file"
    OMARCHY_NIX_FLAKE=$TMPDIR/repo-file/flake.nix omarchy-nix-add install.browser.firefox >/dev/null
    [[ -f $TMPDIR/repo-file/omarchy-packages.json ]] || fail "file form (add)"
    got=$(OMARCHY_NIX_FLAKE=$TMPDIR/repo-file/flake.nix omarchy-update-system-pkgs)
    grep -q "Using flake: $(canon "$TMPDIR/repo-file")" <<<"$got" || fail "file form (update): $got"
    # omarchy update rebuilds with `boot` unless told otherwise (a
    # `switch` can restart the session the updater runs in)
    grep -qxF "DRY-RUN: sudo nixos-rebuild boot --flake $(canon "$TMPDIR/repo-file")" <<<"$got" ||
      fail "update: nixos-rebuild boot is not the default: $got"
    OMARCHY_NIX_FLAKE=$TMPDIR/repo-file/flake.nix omarchy-pkg-present firefox ||
      fail "file form (pkg-present): must see the same JSON"
    echo "file form OK"

    # --- symlink form canonicalizes ---------------------------------
    mkrepo "$TMPDIR/repo-real"
    ln -s "$TMPDIR/repo-real" "$TMPDIR/repo-link"
    got=$(OMARCHY_NIX_FLAKE=$TMPDIR/repo-link omarchy-update-system-pkgs)
    grep -q "Using flake: $(canon "$TMPDIR/repo-real")" <<<"$got" || fail "symlink canonicalization: $got"
    echo "symlink form OK"

    # --- trailing slash and relative-path forms canonicalize ------
    mkrepo "$TMPDIR/repo-slash"
    got=$(OMARCHY_NIX_FLAKE="$TMPDIR/repo-slash/" omarchy-update-system-pkgs)
    grep -q "Using flake: $(canon "$TMPDIR/repo-slash")" <<<"$got" || fail "trailing slash: $got"
    got=$(
      cd "$TMPDIR"
      mkdir -p rel-repo && echo '{ }' >rel-repo/flake.nix
      OMARCHY_NIX_FLAKE=rel-repo omarchy-update-system-pkgs
    )
    grep -q "Using flake: $(canon "$TMPDIR/rel-repo")" <<<"$got" || fail "relative path: $got"
    echo "trailing-slash/relative OK"

    # --- whitespace in the path -------------------------------------
    mkrepo "$TMPDIR/repo with spaces"
    OMARCHY_NIX_FLAKE="$TMPDIR/repo with spaces" omarchy-nix-add install.browser.firefox >/dev/null
    [[ -f "$TMPDIR/repo with spaces/omarchy-packages.json" ]] || fail "whitespace path"
    echo "whitespace OK"

    # --- invalid explicit values FAIL CLOSED (never fall back) ------
    # tripwire: the candidate repo JSON must stay untouched from here
    if OMARCHY_NIX_FLAKE=$TMPDIR/does-not-exist omarchy-nix-add install.gaming.steam >/dev/null 2>err.txt; then
      fail "missing explicit path must fail"
    fi
    grep -q "invalid OMARCHY_NIX_FLAKE" err.txt || fail "add: no structured diagnostics"
    [[ $(jq '.features | length' "$HOME/omarchy-nix/omarchy-packages.json") == 0 ]] ||
      fail "add fell back to another checkout!"

    mkdir -p "$TMPDIR/repo-noflake"
    if OMARCHY_NIX_FLAKE=$TMPDIR/repo-noflake omarchy-nix-remove firefox >/dev/null 2>&1; then
      fail "dir without flake.nix must fail"
    fi
    # the remove picker path (no args) fails closed too
    if OMARCHY_NIX_FLAKE=$TMPDIR/does-not-exist omarchy-nix-remove >/dev/null 2>&1; then
      fail "remove picker must fail on invalid explicit"
    fi
    if OMARCHY_NIX_FLAKE=$TMPDIR/does-not-exist omarchy-update-system-pkgs >up.txt 2>&1; then
      fail "update must fail on invalid explicit"
    fi
    grep -q "invalid OMARCHY_NIX_FLAKE" up.txt || fail "update: no structured diagnostics"
    ! grep -q "Using flake" up.txt || fail "update fell back to another checkout"
    # a file that is NOT named flake.nix is invalid too
    echo x >"$TMPDIR/not-a-flake.nix.txt"
    if OMARCHY_NIX_FLAKE=$TMPDIR/not-a-flake.nix.txt omarchy-nix-add install.gaming.steam >/dev/null 2>&1; then
      fail "non-flake.nix file must fail"
    fi
    # pkg-present: invalid explicit must NOT read the candidate repo's
    # JSON (which DOES contain firefox) — exit 1 + diagnostics
    if OMARCHY_NIX_FLAKE=$TMPDIR/does-not-exist omarchy-pkg-present firefox 2>pp.txt; then
      fail "pkg-present fell back to another checkout"
    fi
    grep -q "invalid OMARCHY_NIX_FLAKE" pp.txt || fail "pkg-present: no diagnostics"
    echo "fail-closed OK"

    # --- library checkout earlier in the fallback order is skipped --
    # A bare omarchy-nix clone (no host config) must not
    # shadow the real consumer flake further down the list -----------
    rm -rf "$HOME/omarchy-nix"
    mkrepo "$HOME/omarchy-nix"               # library clone (no .consumer)
    mkconsumer "$HOME/Projects/omarchy-nix"  # real consumer flake
    omarchy-nix-add install.browser.firefox >/dev/null
    [[ -f $HOME/Projects/omarchy-nix/omarchy-packages.json ]] ||
      fail "library checkout shadowed the consumer flake"
    [[ ! -f $HOME/omarchy-nix/omarchy-packages.json ]] ||
      fail "library checkout was mutated"
    # the host name is compared outside Nix: it must never be spliced
    # into the evaluated expression (a quote in it would change the
    # expression), so it never appears in nix's argv
    grep -q 'nixosConfigurations' "$NIX_ARGV_LOG" || fail "the foreign-library probe never ran"
    if grep -qF "$(uname -n)" "$NIX_ARGV_LOG"; then
      fail "host name spliced into the nix expression: $(grep -F "$(uname -n)" "$NIX_ARGV_LOG" | head -1)"
    fi
    echo "library-skip OK"

    # --- root-owned flake dir (0555, the /etc/nixos shape) ----------
    # (read path only; root-owned add/remove writes are covered by
    # case f of checks.omarchy-nix-transactions)
    mkrepo "$TMPDIR/repo-root"
    chmod 555 "$TMPDIR/repo-root"
    got=$(OMARCHY_NIX_FLAKE=$TMPDIR/repo-root omarchy-update-system-pkgs)
    grep -q "Using flake: $(canon "$TMPDIR/repo-root")" <<<"$got" || fail "root-owned resolve: $got"
    chmod 755 "$TMPDIR/repo-root"
    echo "root-owned OK"

    # --- search path (search -> add chain) honors the file form -----
    export OMARCHY_NIX_INDEX_FILE=$TMPDIR/index.tsv
    printf 'qqq-pkg\tdesc q\t1.0\nwww-pkg\tdesc w\t2.0\n' >"$OMARCHY_NIX_INDEX_FILE"
    mkrepo "$TMPDIR/repo-search"
    OMARCHY_NIX_FLAKE=$TMPDIR/repo-search/flake.nix omarchy-nix-search >/dev/null
    jq -e '.packages | index("qqq-pkg")' "$TMPDIR/repo-search/omarchy-packages.json" >/dev/null ||
      fail "search->add did not write to the resolved repo"
    echo "search path OK"

    touch $out
  ''
