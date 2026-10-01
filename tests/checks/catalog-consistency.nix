# Catalog consistency: every catalog pkg/feature-implied pkg must
# exist in the pinned nixpkgs (eval-time), every cataloged menu id
# must appear rewired in omarchy-menu.jsonc, AND every entry must
# evaluate under a consumer-style unfree/insecure whitelist built
# only from that entry's unfreeNames + insecureNames (regression
# net for hidden unfree deps / getName mismatches / throw-aliases).
{
  self,
  inputs,
  nixpkgs,
  pkgs,
  system,
  ownedPackages,
  ...
}:
let
  inherit (pkgs) lib;
  catalog = import ../../pkgs/omarchy-catalog.nix;
  # Flake-owned derivations the module's managed-packages block
  # resolves as a fallback after nixpkgs attrs (omarchy.ownedPackages).
  # flake.nix passes the same ownedPackagesFor set its module wrapper
  # injects, so there is no copy to keep in sync.
  ownedPkgs = ownedPackages;
  entryPkgs = lib.concatMap (e: e.pkgs or [ ]) (builtins.attrValues catalog.entries);
  featurePkgs = lib.concatMap (f: f.unfreePkgs or [ ]) (builtins.attrValues catalog.features);
  allPkgs = lib.unique (entryPkgs ++ featurePkgs);
  missing = builtins.filter (
    n: !(builtins.hasAttr n pkgs) && !(builtins.hasAttr n ownedPkgs)
  ) allPkgs;
  catalogJson = pkgs.writeText "nix-catalog.json" (builtins.toJSON catalog);
  menu = "${self.packages.${system}.omarchy}/share/omarchy/default/omarchy/omarchy-menu.jsonc";

  # Feature name → attrs to force for the drvPath probe.
  # Keys MUST equal catalog.features (asserted below): a new catalog
  # feature without a probe entry would otherwise pass checks with no
  # consumer-path .drvPath probing. Dotted paths resolve via
  # lib.attrByPath. Module-only features with no package attrs use [].
  featureProbeAttrs = {
    steam = [ "steam" ];
    onepassword = [
      "_1password-gui"
      "_1password-cli"
    ];
    tailscale = [ "tailscale" ];
    ollama = [ "ollama" ];
    # xpadneo is module-only (hardware.xpadneo.enable); catalog
    # unfreePkgs is empty — probe matches that, not linuxPackages.
    xpadneo = [ ];
  };

  # Fail closed if catalog.features and featureProbeAttrs diverge.
  catalogFeatureNames = builtins.attrNames catalog.features;
  probeFeatureNames = builtins.attrNames featureProbeAttrs;
  missingFeatureProbes = lib.subtractLists probeFeatureNames catalogFeatureNames;
  extraFeatureProbes = lib.subtractLists catalogFeatureNames probeFeatureNames;

  getName = pkg: pkg.pname or ((builtins.parseDrvName pkg.name).name);

  # A nixpkgs instance that allows exactly these unfree names (+ base
  # obsidian) and insecure names: the consumer-style whitelist.
  pkgsWithPermits =
    unfreeNames: insecureNames:
    import nixpkgs {
      inherit system;
      overlays = [ ];
      config.allowUnfreePredicate = pkg: builtins.elem (getName pkg) ([ "obsidian" ] ++ unfreeNames);
      config.permittedInsecurePackages = insecureNames;
    };

  # An entry's declared permits and the attrs its probe forces.
  entryProbe =
    e:
    let
      feat = e.feature or null;
      featDef = if feat != null then catalog.features.${feat} or { } else { };
    in
    {
      unfreeNames = (e.unfreeNames or [ ]) ++ (featDef.unfreeNames or [ ]);
      insecureNames = e.insecureNames or [ ];
      attrs =
        if e ? pkgs then
          e.pkgs
        else if feat != null then
          featureProbeAttrs.${feat} or [ ]
        else
          [ ];
    };

  # Force attr.drvPath; tryEval so we can collect all failures.
  # Owned derivations bypass the nixpkgs probe: their drvPath comes
  # from this flake, entry-scoped unfree whitelisting is a
  # nixpkgs-config concern (B0) that never sees them.
  evaluates =
    probePkgs: a:
    (builtins.tryEval (
      if builtins.hasAttr a ownedPkgs then
        builtins.seq ownedPkgs.${a}.drvPath true
      else
        builtins.seq
          (lib.attrByPath (lib.splitString "." a) (throw "catalog probe: no such attr path '${a}'") probePkgs)
          .drvPath
          true
    )).success;

  # Force each attr.drvPath under a nixpkgs instance that only
  # allows this entry's declared unfreeNames (+ base obsidian)
  # and insecureNames.
  probeEntry =
    id: e:
    let
      inherit (entryProbe e) unfreeNames insecureNames attrs;
      probePkgs = pkgsWithPermits unfreeNames insecureNames;
      failed = builtins.filter (a: !(evaluates probePkgs a)) attrs;
    in
    if failed == [ ] then
      null
    else
      "${id}: failed attrs [${builtins.concatStringsSep ", " failed}] with unfreeNames=${builtins.toJSON unfreeNames} insecureNames=${builtins.toJSON insecureNames}";

  probeFailures = builtins.filter (x: x != null) (lib.mapAttrsToList probeEntry catalog.entries);

  # Negative permit probe: every declared permit must be needed.
  # Withdraw one unfree or insecure name at a time and re-run the
  # probe; if every nixpkgs attr of the entry still evaluates, the
  # permit is stale and widens the consumer whitelist for nothing
  # (e.g. an insecure electron the package no longer pulls in).
  # Owned derivations are skipped: entry permits never reach them.
  stalePermitsOf =
    id: e:
    let
      inherit (entryProbe e) unfreeNames insecureNames attrs;
      nixpkgsAttrs = builtins.filter (a: !(builtins.hasAttr a ownedPkgs)) attrs;
      withdrawn =
        map (n: {
          label = "unfree ${n}";
          probePkgs = pkgsWithPermits (lib.remove n unfreeNames) insecureNames;
        }) unfreeNames
        ++ map (n: {
          label = "insecure ${n}";
          probePkgs = pkgsWithPermits unfreeNames (lib.remove n insecureNames);
        }) insecureNames;
    in
    if nixpkgsAttrs == [ ] then
      [ ]
    else
      map (w: "${id}: ${w.label}") (
        builtins.filter (w: lib.all (evaluates w.probePkgs) nixpkgsAttrs) withdrawn
      );

  stalePermits = lib.concatLists (lib.mapAttrsToList stalePermitsOf catalog.entries);

  # Stale permits known in this tree, compared exactly: a new stale
  # permit fails, and so does a listed one that stopped being stale
  # (or was removed from the catalog), so this list cannot rot. Empty
  # since bitwarden's electron-39 permit was dropped (2026-10-01).
  expectedStalePermits = [ ];
  unexpectedStalePermits = lib.subtractLists expectedStalePermits stalePermits;
  vanishedStalePermits = lib.subtractLists stalePermits expectedStalePermits;

  # Structural menu-rewire check: parse the JSONC menu
  # properly (string-aware comment/trailing-comma stripping) and
  # compare exact action tokens instead of substring grep — a
  # prefix-related ID can no longer satisfy another entry's check.
  # The parser lives in jsonc.py (shared with tests/ux.nix).
  menuRewireCheck = pkgs.writeText "menu-rewire-check.py" ''
    import json
    import re
    import sys


    # jsonc_to_json, shared with tests/ux.nix:
    ${builtins.readFile ./jsonc.py}

    menu = json.loads(jsonc_to_json(open(sys.argv[1]).read()))
    catalog = json.load(open(sys.argv[2]))
    catalog_ids = set(catalog["entries"].keys())

    token_re = re.compile(r"omarchy-nix-(add|remove)\s+([A-Za-z0-9._-]+)")
    errors = []

    # Per-entry binding: entry X must itself invoke the exact
    # "omarchy-nix-add X" token (not some prefix or sibling ID).
    add_ids = set()
    remove_ids = set()
    for entry_id, entry in menu.items():
        if not isinstance(entry, dict):
            continue
        action = entry.get("action")
        if not isinstance(action, str):
            continue
        for kind, tok in token_re.findall(action):
            (add_ids if kind == "add" else remove_ids).add(tok)

    for cid in sorted(catalog_ids):
        entry = menu.get(cid)
        if not isinstance(entry, dict):
            errors.append("menu jsonc is missing catalog entry: " + cid)
            continue
        action = entry.get("action")
        if not isinstance(action, str):
            errors.append("catalog entry " + cid + " has a non-string action")
            continue
        exact_tokens = [(tok, kind) for kind, tok in token_re.findall(action)]
        if (cid, "add") not in exact_tokens:
            errors.append("menu entry " + cid + " is not rewired to an exact omarchy-nix-add token: " + action)

    # Per-entry binding for removes: entry "remove.<suffix>" must
    # itself invoke "omarchy-nix-remove install.<suffix>" (entries
    # still pointing at legacy omarchy-remove-* scripts carry no
    # omarchy-nix token and are skipped). After the development
    # menu rewire, remove.development.* entries carry
    # omarchy-nix-remove install.development.* tokens, so this
    # generic token check covers them — no separate development path.
    for entry_id, entry in menu.items():
        if not isinstance(entry, dict) or not entry_id.startswith("remove."):
            continue
        action = entry.get("action")
        if not isinstance(action, str):
            continue
        tokens = [(kind, tok) for kind, tok in token_re.findall(action)]
        if not tokens:
            continue
        expected = "install." + entry_id[len("remove."):]
        if ("remove", expected) not in tokens:
            errors.append("remove entry " + entry_id + " is not rewired to omarchy-nix-remove " + expected + ": " + action)

    extra_adds = add_ids - catalog_ids
    if extra_adds:
        errors.append("menu add-rewires with unknown catalog id: " + ", ".join(sorted(extra_adds)))

    # Manual sync point with the menu rewires in pkgs/omarchy.nix.
    # Re-check on every omarchy-src bump (and whenever install/remove
    # menu entries are rewired to omarchy-nix-{add,remove}).
    expected_removes = {
        "install.browser.chrome",
        "install.browser.edge",
        "install.browser.brave",
        "install.browser.firefox",
        "install.service.dropbox",
        "install.service.tailscale",
        "install.gaming.steam",
        "install.gaming.retroarch",
        "install.gaming.minecraft",
        "install.gaming.heroic",
        "install.gaming.lutris",
        "install.gaming.xbox-controllers",
        "install.development.rails",
        "install.development.go",
        "install.development.python",
        "install.development.zig",
        "install.development.rust",
        "install.development.java",
        "install.development.dotnet",
        "install.development.ocaml",
        "install.development.clojure",
        "install.development.scala",
        "install.development.javascript.node",
        "install.development.javascript.bun",
        "install.development.javascript.deno",
        "install.development.php.php",
        "install.development.elixir.elixir",
    }
    missing_removes = expected_removes - remove_ids
    if missing_removes:
        errors.append("menu jsonc is missing remove rewires: " + ", ".join(sorted(missing_removes)))
    unknown_removes = remove_ids - catalog_ids
    if unknown_removes:
        errors.append("menu remove-rewires with unknown catalog id: " + ", ".join(sorted(unknown_removes)))

    if errors:
        for e in errors:
            print("FAIL: " + e, file=sys.stderr)
        sys.exit(1)
  '';
in
if missing != [ ] then
  throw "omarchy-catalog.nix: attributes missing from pinned nixpkgs: ${builtins.concatStringsSep ", " missing}"
else if missingFeatureProbes != [ ] || extraFeatureProbes != [ ] then
  throw "featureProbeAttrs out of sync with catalog.features: missing from probe [${builtins.concatStringsSep ", " missingFeatureProbes}]; extra in probe [${builtins.concatStringsSep ", " extraFeatureProbes}]"
else if probeFailures != [ ] then
  throw "omarchy-catalog.nix: consumer-path drvPath probe failed:\n  ${builtins.concatStringsSep "\n  " probeFailures}"
else if unexpectedStalePermits != [ ] || vanishedStalePermits != [ ] then
  throw "omarchy-catalog.nix: permit probe mismatch. Stale permits (the entry evaluates without them; drop them from the catalog): [${builtins.concatStringsSep ", " unexpectedStalePermits}]. expectedStalePermits entries no longer stale (drop them from tests/checks/catalog-consistency.nix): [${builtins.concatStringsSep ", " vanishedStalePermits}]"
else
  pkgs.runCommand "omarchy-catalog-consistency" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${menuRewireCheck} ${menu} ${catalogJson}

    # Teeth: the exact-token binding must reject a prefix-sibling
    # ID (substring matching would satisfy entry install.a with
    # the install.a-b token), and must not false-positive on a
    # correctly rewired entry.
    cd "$TMPDIR"
    cat > catalog-fixture.json <<'EOF'
    {"entries": {"install.a": {}, "install.a-b": {}}}
    EOF
    cat > menu-bad.json <<'EOF'
    {"install.a": {"action": "x omarchy-nix-add install.a-b"},
     "install.a-b": {"action": "x omarchy-nix-add install.a-b"}}
    EOF
    if python3 ${menuRewireCheck} menu-bad.json catalog-fixture.json 2>bad.err; then
      echo "menu-rewire checker accepted a prefix-sibling token (no teeth)"
      exit 1
    fi
    grep -q 'install.a is not rewired to an exact omarchy-nix-add token' bad.err || {
      echo "menu-rewire checker failed, but not on the exact-token rule:"
      cat bad.err
      exit 1
    }
    cat > menu-ok.json <<'EOF'
    {"install.a": {"action": "x omarchy-nix-add install.a"},
     "install.a-b": {"action": "x omarchy-nix-add install.a-b"}}
    EOF
    # The fixture carries none of the expected_removes rewires, so the
    # checker must exit 1 with exactly that one FAIL line. Anything
    # else (a traceback, a false positive on install.a) fails here.
    status=0
    python3 ${menuRewireCheck} menu-ok.json catalog-fixture.json 2>ok.err || status=$?
    if [ "$status" -ne 1 ] || [ "$(wc -l <ok.err)" -ne 1 ] ||
      ! grep -q '^FAIL: menu jsonc is missing remove rewires: ' ok.err; then
      echo "menu-rewire checker: unexpected result on a correctly rewired entry (exit $status):"
      cat ok.err
      exit 1
    fi
    touch $out
  ''
