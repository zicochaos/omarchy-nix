# Behavioral check for the quickshell menu guard batch: generate
# the exact bash batch MenuModel.js runs (parse shipped menu →
# merge → guardScript) and execute it against a fixture consumer
# state. Catches the NixOS regression where the batch's
# pacman-backed omarchy-pkg-present shadow always answered
# "missing", so every Install row rendered available and Remove
# rows never appeared. NixOS has no pacman, so a sandbox run is a
# faithful NixOS reproduction — with the delegation patch the
# batch must report managed packages as present through the same
# catalog → omarchy-packages.json → binaries resolution the real
# probe uses.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  # The resolver's foreign-library probe (one nix eval per discovery
  # candidate): answers "this host is configured here" and counts the
  # call in $NIX_EVAL_COUNT.
  stubNix = pkgs.writeShellScript "stub-nix" ''
    echo x >>"$NIX_EVAL_COUNT"
    printf '["%s"]\n' "$(uname -n)"
  '';
in
pkgs.runCommand "omarchy-menu-guards-check"
  {
    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.jq
    ];
    env.OMARCHY_PATH = "${omarchyPkg}/share/omarchy";
  }
  ''
    set -euo pipefail
    fail() { echo "FAIL: $*" >&2; exit 1; }

    # Consumer-state fixture: rustc/cargo/firefox managed, brave
    # absent. resolve_flake_dir requires a flake.nix in the dir.
    export OMARCHY_NIX_FLAKE="$PWD/consumer-flake"
    mkdir -p "$OMARCHY_NIX_FLAKE"
    : > "$OMARCHY_NIX_FLAKE/flake.nix"
    printf '{"packages": ["rustc", "cargo", "firefox"], "features": []}\n' \
      > "$OMARCHY_NIX_FLAKE/omarchy-packages.json"

    cat > gen-guard-script.js <<'JS'
    const M = require(process.env.OMARCHY_PATH + "/shell/plugins/menu/MenuModel.js");
    const fs = require("fs");
    const defaults = M.parseMenuJsonc(
      fs.readFileSync(process.env.OMARCHY_PATH + "/default/omarchy/omarchy-menu.jsonc", "utf8"),
    );
    const merged = M.mergeMenuSources(defaults, []);
    process.stdout.write(M.guardScript(merged.items));
    JS

    node gen-guard-script.js > guard.sh
    [ -s guard.sh ] || fail "empty guard script"

    # A nonzero batch makes the shell drop ALL guard results, so
    # the exit status is part of the contract.
    bash guard.sh > results.txt ||
      fail "guard batch exited nonzero (shell would discard every result)"

    grep -qx 'install.development.rust:d:1' results.txt ||
      fail "rust reported not installed (menu would offer it again)"
    grep -qx 'install.browser.firefox:d:1' results.txt ||
      fail "firefox reported not installed"
    grep -qx 'install.browser.brave:d:0' results.txt ||
      fail "brave wrongly reported installed"
    grep -qx 'remove.development.rust:w:1' results.txt ||
      fail "remove-rust row not visible despite rust installed"

    # Login-shell hardening: production runs the batch via
    # `bash -lc`, so a user profile flipping shell options must
    # not kill it. Apply the strictest profile directly to the
    # batch shell instead of relying on sandbox /etc/profile.
    bash -euo pipefail -c "$(cat guard.sh)" > results-strict.txt ||
      fail "guard batch died under errexit/nounset"
    grep -qx 'install.development.rust:d:1' results-strict.txt ||
      fail "strict-flags run lost results"

    # Batch-level flake resolution: without an explicit
    # OMARCHY_NIX_FLAKE the prelude resolves the consumer flake
    # once (first discovery candidate) and every probe must
    # agree with the managed state through that export. Discovery
    # costs a nix eval per candidate, so the batch must resolve
    # exactly once — the stub nix counts the evals.
    mkdir -p stub
    ln -s ${stubNix} stub/nix
    mkdir -p fake-home/omarchy-nix
    printf '{"packages": ["rustc", "cargo", "firefox"], "features": []}\n' \
      > fake-home/omarchy-nix/omarchy-packages.json
    : > fake-home/omarchy-nix/flake.nix
    : > evals-discovery
    env -u OMARCHY_NIX_FLAKE HOME=$PWD/fake-home NIX_EVAL_COUNT=$PWD/evals-discovery \
      PATH=$PWD/stub:$PATH bash guard.sh > results-discovery.txt ||
      fail "guard batch failed without explicit OMARCHY_NIX_FLAKE"
    grep -qx 'install.development.rust:d:1' results-discovery.txt ||
      fail "batch-level flake resolution did not reach the probes"
    [[ $(wc -l < evals-discovery) == 1 ]] ||
      fail "$(wc -l < evals-discovery) flake resolutions for one guard batch (want 1)"

    # The same before the first install: a consumer flake without
    # omarchy-packages.json yet still resolves once per batch (every
    # catalog probe used to re-run discovery, nix eval included).
    mkdir -p fresh-home/omarchy-nix
    : > fresh-home/omarchy-nix/flake.nix
    : > evals-fresh
    env -u OMARCHY_NIX_FLAKE HOME=$PWD/fresh-home NIX_EVAL_COUNT=$PWD/evals-fresh \
      PATH=$PWD/stub:$PATH bash guard.sh > results-fresh.txt ||
      fail "guard batch failed before the first install"
    grep -qx 'install.browser.brave:d:0' results-fresh.txt ||
      fail "fresh install: brave reported installed"
    [[ $(wc -l < evals-fresh) == 1 ]] ||
      fail "fresh install: $(wc -l < evals-fresh) flake resolutions for one guard batch (want 1)"

    touch $out
  ''
