{
  description = "NixOS port of basecamp/omarchy (Quattro generation)";

  inputs = {
    # Stable nixpkgs (26.05) so consumers on a stable NixOS install do NOT get
    # shifted to unstable by `nixos-rebuild switch --flake`. Hyprland >= 0.56
    # (the Quattro Lua config requirement — stable only has 0.55.4) comes from
    # the separate `hyprland` flake input below, which is self-contained (it
    # builds against its own nixpkgs, not this one).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Upstream Omarchy is NOT a flake; we vendor the quattro branch tree as a
    # derivation (see pkgs/omarchy.nix). Update with:
    #   nix flake lock --update-input omarchy-src
    omarchy-src = {
      url = "github:basecamp/omarchy/quattro";
      flake = false;
    };

    # Hyprland needs to be >= 0.56 for the Lua config Quattro uses.
    hyprland.url = "github:hyprwm/Hyprland";

    # Home-Manager pinned to the release branch matching stable nixpkgs
    # (26.05). Following the rolling master branch pulled a 26.11-pre HM
    # into a 26.05 system and tripped the state-version mismatch warning
    # on every evaluation.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # quickshell: prefer pkgs.quickshell (nixpkgs tracks the v0.3.0 release).
    # If upstream shell.qml needs a newer API, add an explicit input:
    #   quickshell.url = "github:quickshell-mirror/quickshell";
    # and use inputs.quickshell.packages.${system}.quickshell in the NixOS
    # module. Decided when the shell first loads in a VM, not before.
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      omarchy-src,
      hyprland,
      home-manager,
      ...
    }:
    let
      # x86_64-only for now: the checks do not pass evaluation on aarch64
      # (hardware.graphics.enable32Bit is x86_64-only), so advertising the
      # arch was broken-by-declaration. Re-add when the checks evaluate
      # there (tracked on the dev tracker).
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # Read the upstream version file (e.g. "4.0.0.alpha"). It carries a
      # trailing newline — trim it once here so every consumer (package names,
      # derivation paths, meta) sees the clean value.
      omarchyVersion = nixpkgs.lib.strings.trim (builtins.readFile "${omarchy-src}/version");

      # Shared omarchy.* option schema. Imported by both the NixOS module and
      # the Home-Manager module so consumers set options once at the system
      # level and HM mirrors them via osConfig.
      omarchyOptions = import ./config.nix;

      # External pkgs for packages/demo/tests. Global allowUnfree is
      # intentionally NOT set — it used to mask the real consumer path
      # (B0 allowUnfreePredicate) and let broken catalog unfreeNames slip
      # through. The default app set needs obsidian; the ux fixture enables
      # the steam feature while nixpkgs.pkgs isDefined (B0 skipped), so steam
      # + steam-unwrapped must live here too. Menu installs on the real
      # consumer path (no external pkgs) are covered by B0 from the catalog.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "obsidian"
              "steam"
              "steam-unwrapped"
            ];
        };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      # Vendoring derivation. The upstream tree lands at
      # $out/share/omarchy (the NixOS analogue of pacman's /usr/share/omarchy).
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          omarchy = pkgs.callPackage ./pkgs/omarchy.nix {
            inherit omarchy-src;
            version = omarchyVersion;
            # Path-adaptation deps for the 7 systemd user units (see pkgs/omarchy.nix).
            # bluez-tools provides bt-agent (not bluez); tailscale is only used
            # for ConditionPathExists / ExecStart path rewrite — the unit is
            # shipped but not enabled by the module.
            fcitx5 = pkgs.fcitx5;
            bluez-tools = pkgs.bluez-tools;
            pipewire = pkgs.pipewire;
            systemd = pkgs.systemd;
            tailscale = pkgs.tailscale;
          };
          # Plymouth boot-splash theme + SDDM login theme/Hyprland greeter.
          # Consumed by the omarchy NixOS module (boot.plymouth.themePackages
          # and services.displayManager.sddm theme wiring); also exposed for
          # standalone use.
          plymouth-omarchy-theme = pkgs.callPackage ./pkgs/plymouth-omarchy-theme.nix {
            inherit omarchy-src;
            version = omarchyVersion;
          };
          sddm-omarchy-theme = pkgs.callPackage ./pkgs/sddm-omarchy-theme.nix {
            inherit omarchy-src;
            version = omarchyVersion;
          };
          # Upstream-owned apps that are not in nixpkgs.
          # aether: theme generator (Wails). asdcontrol: Apple Studio Display
          # brightness. omacut: video cutter (needs ffmpeg on PATH at runtime).
          # omawrite: markdown writer. tensaku: screenshot annotator.
          # try: tobi's experiment-worktree CLI. hyprland-guiutils: hyprwm
          # dialog/run/welcome tools. hyprland-preview-share-picker: xdp
          # screencopy picker. omarchy-nvim: LazyVim starter + omarchy overlay.
          aether = pkgs.callPackage ./pkgs/aether.nix { };
          asdcontrol = pkgs.callPackage ./pkgs/asdcontrol.nix { };
          omacut = pkgs.callPackage ./pkgs/omacut.nix { };
          omawrite = pkgs.callPackage ./pkgs/omawrite.nix { };
          tensaku = pkgs.callPackage ./pkgs/tensaku.nix { };
          try = pkgs.callPackage ./pkgs/try.nix { };
          hyprland-guiutils = pkgs.callPackage ./pkgs/hyprland-guiutils.nix { };
          hyprland-preview-share-picker = pkgs.callPackage ./pkgs/hyprland-preview-share-picker.nix { };
          omarchy-nvim = pkgs.callPackage ./pkgs/omarchy-nvim.nix { };
          omarchy-fish = pkgs.callPackage ./pkgs/omarchy-fish.nix { };
          # Icons for stock Omarchy themes (nixpkgs dropped yaru-theme with murrine).
          yaru-theme = pkgs.callPackage ./pkgs/yaru-theme.nix { };
          default = self.packages.${system}.omarchy;
        }
      );

      # NixOS module: enables Hyprland + quickshell + the omarchy runtime deps
      # and wires OMARCHY_PATH.
      #
      # This is the *flake wrapper*: it imports the pure module and injects the
      # flake-specific defaults. We also import upstream's
      # `hyprland.nixosModules.default`, which both pins Hyprland to the
      # `hyprland` input (>= 0.56 for the Lua config) and links `/share/hypr`
      # so Hyprland's Lua config provider can find the vendored config. The
      # pure module in modules/nixos/default.nix contains no flake references.
      nixosModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          imports = [
            inputs.hyprland.nixosModules.default
            ./modules/nixos/default.nix
          ];

          config = lib.mkMerge [
            {
              # Inject the vendored omarchy derivation as the module default.
              # Consumers can override with omarchy.package = <derivation>.
              omarchy.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
              # Inject the system-theme packages (Plymouth + SDDM) so the pure
              # module can wire them without referencing the flake.
              omarchy.plymouthPackage =
                lib.mkDefault
                  self.packages.${pkgs.stdenv.hostPlatform.system}.plymouth-omarchy-theme;
              omarchy.sddmPackage =
                lib.mkDefault
                  self.packages.${pkgs.stdenv.hostPlatform.system}.sddm-omarchy-theme;

              # Inject the upstream-owned apps (not in nixpkgs, built under
              # pkgs/) so the pure module ships them without referencing the
              # flake. Consumers can drop entries with omarchy.exclude_packages
              # or override the whole list.
              omarchy.appPackages = lib.mkDefault (
                with self.packages.${pkgs.stdenv.hostPlatform.system};
                [
                  aether
                  asdcontrol
                  omacut
                  omawrite
                  tensaku
                  try
                  hyprland-guiutils
                  hyprland-preview-share-picker
                  omarchy-nvim
                  # Yaru-* icons: not pkgs.yaru-theme (throw-alias on new nixpkgs).
                  yaru-theme
                ]
              );
              omarchy.nvimPackage = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy-nvim;
              omarchy.fish.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy-fish;
            }

            # Pin mesa to the hyprland input's nixpkgs. Stable nixpkgs mesa
            # can lag behind the Hyprland flake's expectations, causing 3D lag
            # in GPU apps. Using the same mesa Hyprland itself builds against
            # avoids the mismatch. mkOverride 500 wins over nixpkgs' mkDefault
            # (1000) but a consumer's plain = (100) still overrides this.
            # Guarded by omarchy.enable: merely IMPORTING the module
            # must not change the host's Mesa.
            (lib.mkIf config.omarchy.enable {
              hardware.graphics.package =
                lib.mkOverride 500
                  inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.mesa;
            })
          ];
        };

      # Home-Manager module: seeds the Hyprland Lua entry point and the user
      # omarchy config (~/.config/omarchy, ~/.config/hypr).
      homeManagerModules.default =
        { ... }:
        {
          imports = [ ./modules/home-manager/default.nix ];
        };

      # NixOS test harness (Stage 5): boots a VM with virtio-gpu-pci and
      # asserts the full desktop stack comes up — Hyprland + quickshell bar +
      # launcher. Runs automatically under `nix flake check` and protects the
      # port against regressions (new upstream rev, dep changes, refactors).
      #
      # testers.nixosTest calls the test module as `lib.toFunction test pkgs`,
      # so it can only pass `pkgs`. To let tests/desktop.nix import the flake
      # modules, we hand it `self` and the home-manager input by applying the
      # test function here (closure), then passing the resulting test record.
      checks = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          # testers.nixosTest calls the test module as `lib.toFunction test pkgs`,
          # so it can only pass `pkgs`. Apply the function here (closure) to hand
          # each test the flake modules it imports (self + home-manager), then
          # pass the resulting record. See tests/desktop.nix + tests/ux.nix.
          loadTest =
            file:
            (import file) {
              inherit pkgs;
              lib = pkgs.lib;
              omarchy = self;
              home-manager = inputs.home-manager;
            };
        in
        {
          omarchy-desktop = pkgs.testers.nixosTest (loadTest ./tests/desktop.nix);
          # UX/acceptance test: exercises real user behavior (Super+Enter ->
          # foot, session env, default browser, cursor, first-run, systemd user
          # units) on top of the desktop.nix baseline. See tests/ux.nix.
          omarchy-ux = pkgs.testers.nixosTest (loadTest ./tests/ux.nix);
          # Fish profile acceptance: login shell, vendor dirs, session env,
          # completion contract, override precedence. See tests/fish.nix.
          omarchy-fish = pkgs.testers.nixosTest (loadTest ./tests/fish.nix);
          # The packaged agent skill is an intentional NixOS adaptation of
          # upstream's Arch-only default. Keep the repository copy and the
          # installed $OMARCHY_PATH copy byte-identical, and reject the
          # dangerous Arch package-management guidance this port replaces.
          omarchy-skill =
            let
              sourceSkill = ./skills/omarchy/SKILL.md;
              packagedSkill = "${self.packages.${system}.omarchy}/share/omarchy/default/omarchy-skill/SKILL.md";
              upstreamSkill = "${inputs.omarchy-src}/default/omarchy-skill/SKILL.md";
              parityManifest = ./skills/omarchy/skill-parity.json;
            in
            pkgs.runCommand "omarchy-skill-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              cmp ${sourceSkill} ${packagedSkill}

              grep -Fq "name: omarchy" ${packagedSkill}
              grep -Fq "Omarchy on NixOS" ${packagedSkill}
              grep -Fq "\$OMARCHY_PATH" ${packagedSkill}
              grep -Fq "OMARCHY_NIX_FLAKE" ${packagedSkill}
              grep -Fq "omarchy-nix-search" ${packagedSkill}
              grep -Fq "omarchy-nix-add" ${packagedSkill}
              grep -Fq "omarchy-nix-remove" ${packagedSkill}
              grep -Fq "nixos-rebuild" ${packagedSkill}
              grep -Fq 'Do not use `pacman`, `yay`' ${packagedSkill}

              ! grep -Fq "beautiful, modern, opinionated Arch Linux distribution" ${packagedSkill}
              ! grep -Fq "omarchy pkg aur add" ${packagedSkill}
              ! grep -Fq "/usr/share/omarchy" ${packagedSkill}

              # --- Semantic parity against the upstream skill ---------------
              # Every upstream h2-h4 (##+) heading and every Command Groups
              # table row must be classified in skill-parity.json (preserved /
              # adapted / omitted-with-reason) — and nothing stale may linger
              # in the manifest. A new upstream section or group fails this
              # check until it is classified.
              grep -E '^##{1,3} ' ${upstreamSkill} |
                sed -E 's/^##{1,3} //' | LC_ALL=C sort > upstream-sections.txt
              jq -r '.sections | keys[]' ${parityManifest} | LC_ALL=C sort > manifest-sections.txt
              if ! diff -u upstream-sections.txt manifest-sections.txt; then
                echo "FAIL: upstream skill sections diverge from skill-parity.json" >&2
                echo "(< unclassified upstream section, > stale manifest entry)" >&2
                exit 1
              fi

              grep -oE '^\| `omarchy [A-Za-z0-9_-]+` ' ${upstreamSkill} |
                sed -E 's/^\| `omarchy ([A-Za-z0-9_-]+)`.*/\1/' | LC_ALL=C sort > upstream-groups.txt
              jq -r '.commandGroups | keys[]' ${parityManifest} | LC_ALL=C sort > manifest-groups.txt
              if ! diff -u upstream-groups.txt manifest-groups.txt; then
                echo "FAIL: upstream command groups diverge from skill-parity.json" >&2
                echo "(< unclassified upstream group, > stale manifest entry)" >&2
                exit 1
              fi

              # Statuses are from the closed set; omitted REQUIRES a reason.
              jq -e '[.sections[], .commandGroups[] | .status] |
                     all(. == "preserved" or . == "adapted" or . == "omitted")' \
                ${parityManifest} >/dev/null ||
                { echo "FAIL: invalid status in skill-parity.json" >&2; exit 1; }
              jq -e '[.sections[], .commandGroups[] | select(.status == "omitted")] |
                     all(has("reason") and (.reason | length > 0))' \
                ${parityManifest} >/dev/null ||
                { echo "FAIL: omitted entry without a reason in skill-parity.json" >&2; exit 1; }

              # Anchors for the adapted coverage the manifest claims.
              grep -Fq "## Privilege Escalation" ${packagedSkill}
              grep -Fq "/run/wrappers/bin/sudo" ${packagedSkill}
              grep -Fq "### Other Configs" ${packagedSkill}
              grep -Fq "omarchy font set" ${packagedSkill}
              grep -Fq "omarchy system lock" ${packagedSkill}
              grep -Fq "## Out of Scope" ${packagedSkill}
              grep -Fq "## Example Requests" ${packagedSkill}
              grep -Fq "nix-add" ${packagedSkill}

              # Manifest-driven anchors: every entry carrying an 'anchor'
              # string must have that string present in our SKILL.md — this
              # proves classified content (esp. preserved sections/groups) is
              # actually there, not just classified.
              jq -r '[.sections[], .commandGroups[] | select(has("anchor")) | .anchor] | .[]' \
                ${parityManifest} > parity-anchors.txt
              while IFS= read -r anchor; do
                grep -Fq -- "$anchor" ${packagedSkill} ||
                  { echo "FAIL: parity anchor missing from SKILL.md: $anchor" >&2; exit 1; }
              done < parity-anchors.txt

              touch "$out"
            '';
          # Catalog consistency: every catalog pkg/feature-implied pkg must
          # exist in the pinned nixpkgs (eval-time), every cataloged menu id
          # must appear rewired in omarchy-menu.jsonc, AND every entry must
          # evaluate under a consumer-style unfree/insecure whitelist built
          # only from that entry's unfreeNames + insecureNames (regression
          # net for hidden unfree deps / getName mismatches / throw-aliases).
          catalog-consistency =
            let
              inherit (pkgs) lib;
              catalog = import ./pkgs/omarchy-catalog.nix;
              entryPkgs = lib.concatMap (e: e.pkgs or [ ]) (builtins.attrValues catalog.entries);
              featurePkgs = lib.concatMap (f: f.unfreePkgs or [ ]) (builtins.attrValues catalog.features);
              allPkgs = lib.unique (entryPkgs ++ featurePkgs);
              missing = builtins.filter (n: !(builtins.hasAttr n pkgs)) allPkgs;
              catalogJson = pkgs.writeText "nix-catalog.json" (builtins.toJSON catalog);
              menu = "${self.packages.${system}.omarchy}/share/omarchy/default/omarchy/omarchy-menu.jsonc";

              # Feature name → attrs to force for the drvPath probe.
              # Dotted paths are resolved with lib.attrByPath (kernel module
              # packages live under linuxPackages, e.g. xpadneo).
              featureProbeAttrs = {
                steam = [ "steam" ];
                onepassword = [
                  "_1password-gui"
                  "_1password-cli"
                ];
                tailscale = [ "tailscale" ];
                ollama = [ "ollama" ];
                xpadneo = [ "linuxPackages.xpadneo" ];
              };

              getName = pkg: pkg.pname or ((builtins.parseDrvName pkg.name).name);

              # Force each attr.drvPath under a nixpkgs instance that only
              # allows this entry's declared unfreeNames (+ base obsidian)
              # and insecureNames. tryEval so we can collect all failures.
              probeEntry =
                id: e:
                let
                  feat = e.feature or null;
                  featDef = if feat != null then catalog.features.${feat} or { } else { };
                  unfreeNames = (e.unfreeNames or [ ]) ++ (featDef.unfreeNames or [ ]);
                  insecureNames = e.insecureNames or [ ];
                  attrs =
                    if e ? pkgs then
                      e.pkgs
                    else if feat != null then
                      featureProbeAttrs.${feat} or [ ]
                    else
                      [ ];
                  probePkgs = import nixpkgs {
                    inherit system;
                    config.allowUnfreePredicate = pkg: builtins.elem (getName pkg) ([ "obsidian" ] ++ unfreeNames);
                    config.permittedInsecurePackages = insecureNames;
                  };
                  failed = builtins.filter (
                    a:
                    let
                      r = builtins.tryEval (
                        builtins.seq
                          (lib.attrByPath (lib.splitString "." a) (throw "catalog probe: no such attr path '${a}'") probePkgs)
                          .drvPath
                          true
                      );
                    in
                    !r.success
                  ) attrs;
                in
                if failed == [ ] then
                  null
                else
                  "${id}: failed attrs [${builtins.concatStringsSep ", " failed}] with unfreeNames=${builtins.toJSON unfreeNames} insecureNames=${builtins.toJSON insecureNames}";

              probeFailures = builtins.filter (x: x != null) (lib.mapAttrsToList probeEntry catalog.entries);

              # Structural menu-rewire check: parse the JSONC menu
              # properly (string-aware comment/trailing-comma stripping) and
              # compare exact action tokens instead of substring grep — a
              # prefix-related ID can no longer satisfy another entry's check.
              menuRewireCheck = pkgs.writeText "menu-rewire-check.py" ''
                import json
                import re
                import sys


                def jsonc_to_json(text):
                    out = []
                    i = 0
                    n = len(text)
                    in_str = False
                    while i < n:
                        c = text[i]
                        if in_str:
                            out.append(c)
                            if c == "\\":
                                if i + 1 < n:
                                    out.append(text[i + 1])
                                    i += 2
                                    continue
                            elif c == "\"":
                                in_str = False
                            i += 1
                            continue
                        if c == "\"":
                            in_str = True
                            out.append(c)
                            i += 1
                        elif c == "/" and i + 1 < n and text[i + 1] == "/":
                            while i < n and text[i] != "\n":
                                i += 1
                        elif c == "/" and i + 1 < n and text[i + 1] == "*":
                            i += 2
                            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                                i += 1
                            i += 2
                        elif c == ",":
                            j = i + 1
                            while j < n and text[j] in " \t\r\n":
                                j += 1
                            if j < n and text[j] in "}]":
                                i += 1
                            else:
                                out.append(c)
                                i += 1
                        else:
                            out.append(c)
                            i += 1
                    return "".join(out)


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
                # omarchy-nix token and are skipped).
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
            else if probeFailures != [ ] then
              throw "omarchy-catalog.nix: consumer-path drvPath probe failed:\n  ${builtins.concatStringsSep "\n  " probeFailures}"
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
                python3 ${menuRewireCheck} menu-ok.json catalog-fixture.json 2>ok.err || true
                if grep -q 'install.a is not rewired' ok.err; then
                  echo "menu-rewire checker false-positives on a correctly rewired entry:"
                  cat ok.err
                  exit 1
                fi
                touch $out
              '';
          # Migration manifest consistency: every vendored
          # migration must be classified in pkgs/omarchy-migrations.nix
          # (unclassified = fail), every manifest key must exist in the
          # vendored set (stale = fail), and every "adapter" class must have
          # its replacement script in pkgs/migrations-nix/.
          omarchy-migrations =
            let
              manifestJson = pkgs.writeText "migrations-nix.json" (
                builtins.toJSON (import ./pkgs/omarchy-migrations.nix)
              );
              vendored = "${self.packages.${system}.omarchy}/share/omarchy/migrations";
              adapters = ./pkgs/migrations-nix;
            in
            pkgs.runCommand "omarchy-migrations-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              ls ${vendored}/*.sh | xargs -n1 basename | sort > vendored.txt
              jq -r 'keys[]' ${manifestJson} | sort > manifest.txt

              unclassified=$(comm -23 vendored.txt manifest.txt)
              if [[ -n $unclassified ]]; then
                echo "vendored migrations missing from pkgs/omarchy-migrations.nix:"
                echo "$unclassified"
                exit 1
              fi

              stale=$(comm -13 vendored.txt manifest.txt)
              if [[ -n $stale ]]; then
                echo "stale keys in pkgs/omarchy-migrations.nix (not vendored anymore):"
                echo "$stale"
                exit 1
              fi

              for f in $(jq -r 'to_entries[] | select(.value == "adapter") | .key' ${manifestJson}); do
                [[ -f ${adapters}/$f ]] || { echo "adapter classified but missing: pkgs/migrations-nix/$f"; exit 1; }
              done

              bad=$(jq -r 'to_entries[] | select(.value != "skip" and .value != "user-safe" and .value != "adapter") | .key' ${manifestJson})
              if [[ -n $bad ]]; then
                echo "unknown migration class (want skip|user-safe|adapter):"
                echo "$bad"
                exit 1
              fi

              touch $out
            '';
          # Shebang coverage: every executable shipped in the
          # package must resolve to a Nix store interpreter — no /usr/bin
          # or /usr/bin/env leftovers (NixOS has neither).
          omarchy-shebangs =
            let
              omarchyPkg = self.packages.${system}.omarchy;
            in
            pkgs.runCommand "omarchy-shebang-check" { } ''
              bad=0
              while IFS= read -r f; do
                first=$(head -n1 "$f" || true)
                case "$first" in
                  '#!'*) ;;
                  *) continue ;;
                esac
                interp=''${first#\#!}
                interp=''${interp#"''${interp%%[![:space:]]*}"}
                case "$interp" in
                  /nix/store/*) ;;
                  *)
                    echo "unpatched interpreter: $f -> $first"
                    bad=1
                    ;;
                esac
              done < <(find ${omarchyPkg} -type f -perm -u+x)
              [[ $bad == 0 ]] || exit 1
              touch $out
            '';
          # Lock-screen PAM defaults: the password service must
          # always be declared by the module, while the fingerprint service
          # must stay absent unless the consumer opts in via
          # omarchy.fingerprint.enable (the demo config below does not).
          # Opt-in presence is exercised at runtime by VM test section (4h).
          omarchy-pam-eval =
            let
              pamServices = self.nixosConfigurations.demo.config.security.pam.services;
            in
            if !(pamServices ? omarchy-lock-password) then
              throw "demo config is missing the omarchy-lock-password PAM service (must always be declared)"
            else if (pamServices ? omarchy-lock-fingerprint) then
              throw "demo config has omarchy-lock-fingerprint without omarchy.fingerprint.enable"
            else
              pkgs.runCommand "omarchy-pam-eval" { } "touch $out";
          # binfmt plumbing: the opt-in list must stay empty on
          # the demo config (no silent emulation) and reach
          # boot.binfmt.emulatedSystems unchanged when set. extendModules
          # derives the positive case from the demo config.
          omarchy-binfmt-eval =
            let
              demoCfg = self.nixosConfigurations.demo.config;
              withBinfmt =
                (self.nixosConfigurations.demo.extendModules {
                  modules = [ { omarchy.binfmtEmulatedSystems = [ "aarch64-linux" ]; } ];
                }).config;
            in
            if demoCfg.boot.binfmt.emulatedSystems != [ ] then
              throw "demo config must keep boot.binfmt.emulatedSystems empty by default"
            else if withBinfmt.boot.binfmt.emulatedSystems != [ "aarch64-linux" ] then
              throw "omarchy.binfmtEmulatedSystems does not reach boot.binfmt.emulatedSystems"
            else
              pkgs.runCommand "omarchy-binfmt-eval" { } "touch $out";
          # Migration parity: the upstream /etc defaults that migrations
          # 1784568652 (NM-wait-online mask), 1784970000 (logind inhibit
          # delay) and 1784914435 (Wi-Fi powersave off) apply imperatively on
          # Arch must be declared natively by the module, and the vendored
          # chromium-flags.conf seed must carry no Arch /usr/share path (the
          # postPatch rewrite to the system-profile path).
          omarchy-migration-parity =
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
              '';
          # Disabled-state contract: merely IMPORTING
          # nixosModules.default with omarchy.enable = false must not change
          # the host. Compare a baseline system against one importing the
          # disabled module over the observable surface (Mesa, packages,
          # sessions, /etc, caches, hyprland). The second assertion guards the
          # other half of the contract: with omarchy enabled, the demo config
          # still selects the Hyprland-input Mesa (consumer override is a
          # plain `=`, which wins over mkOverride 500 by definition).
          omarchy-disabled-state =
            let
              base = {
                system.stateVersion = "26.05";
                # A real consumer has graphics enabled (via their desktop or
                # explicitly); that is what gives hardware.graphics.package
                # its stable-nixpkgs Mesa default to be clobbered.
                hardware.graphics.enable = true;
              };
              baseline = nixpkgs.lib.nixosSystem {
                inherit pkgs;
                modules = [ base ];
              };
              disabled = nixpkgs.lib.nixosSystem {
                inherit pkgs;
                modules = [
                  base
                  self.nixosModules.default
                  { omarchy.enable = false; }
                ];
              };
              observables = c: {
                mesa = c.hardware.graphics.package.drvPath;
                mesa32 = c.hardware.graphics.package32.drvPath;
                systemPackages = builtins.sort (a: b: a < b) (
                  map (p: p.name or "unknown") c.environment.systemPackages
                );
                sessionPackages = map (p: p.name or "unknown") c.services.displayManager.sessionPackages;
                sddm = c.services.displayManager.sddm.enable;
                hyprland = c.programs.hyprland.enable;
                etcNames = builtins.attrNames c.environment.etc;
                substituters = c.nix.settings.substituters or [ ];
              };
              hyprlandMesa = inputs.hyprland.inputs.nixpkgs.legacyPackages.${system}.mesa.drvPath;
            in
            if observables baseline.config != observables disabled.config then
              throw "nixosModules.default has import-time side effects with omarchy.enable = false"
            else if self.nixosConfigurations.demo.config.hardware.graphics.package.drvPath != hyprlandMesa then
              throw "enabled omarchy no longer selects the Hyprland-input Mesa"
            else
              pkgs.runCommand "omarchy-disabled-state" { } "touch $out";
          # Runtime mutator quarantine: scan every packaged bin/
          # script for forbidden Arch mutation patterns. A script with a hit
          # must be classified in pkgs/omarchy-runtime-manifest.nix;
          # declarative-note/nixos-adapted classes must scan clean, user-safe
          # may only keep its declared `allow` groups. A NEW upstream mutator
          # is unclassified and FAILS the build — classification is forced at
          # bump time. Also verifies the hidden menu ids are gone and no menu
          # entry references a stubbed mutator.
          omarchy-runtime =
            let
              omarchyPkg = self.packages.${system}.omarchy;
              manifestJson = pkgs.writeText "omarchy-runtime-manifest.json" (
                builtins.toJSON (import ./pkgs/omarchy-runtime-manifest.nix)
              );
            in
            pkgs.runCommand "omarchy-runtime-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
              bin=${omarchyPkg}/share/omarchy/bin
              menu=${omarchyPkg}/share/omarchy/default/omarchy/omarchy-menu.jsonc
              manifest=${manifestJson}
              bad=0

              declare -A pat
              pat[pacman]='\bpacman[[:space:]]+-'
              pat[pkg-helpers]='\b(yay|paru|makepkg)[[:space:]]'
              pat[ufw]='\bufw[[:space:]]'
              pat[systemctl-system]='systemctl[[:space:]]+(enable|disable|mask|unmask)([[:space:]]|$)'
              # transient system-service control (no persistent config)
              pat[systemctl-restart]='systemctl[[:space:]]+(start|stop|restart|reload|try-restart|reload-or-restart)([[:space:]]|$)'
              pat[systemctl-user]='systemctl[[:space:]]+--user[[:space:]]+(enable|disable|mask|unmask|start|stop|restart)'
              pat[etc-sysconf]='/etc/(pam\.d|sudoers|fstab|systemd/system|systemd/resolved|systemd/network|NetworkManager|mkinitcpio|modprobe\.d|modules-load\.d|omarchy\.conf|limine|opt/chrome|opt/edge|brave|chromium|php)'
              # write verbs targeting /etc (over-matches reads like cp /etc/skel
              # on purpose — classification then audits them)
              pat[etc-write]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/etc/|/etc$)|(>>?)[[:space:]]*/etc/'
              pat[boot-write]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/boot/|/boot$)|(>>?)[[:space:]]*/boot/'
              pat[usr-share]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/usr/share/|/usr/share$)|(>>?)[[:space:]]*/usr/share/'
              pat[usr-lib]='/usr/lib/(systemd|modules)'
              pat[initrd-boot]='\b(mkinitcpio|limine-mkinitcpio|limine-update|limine-snapper-sync|plymouth-set-default-theme|grub-mkconfig|update-grub|efibootmgr|bootctl)\b'
              pat[modprobe]='\b(modprobe|insmod|rmmod)\b'
              pat[kernel-ctl]='\bsysctl[[:space:]]+(-w|--write|-p[[:space:]])'
              pat[account-tools]='\b(usermod|useradd|userdel|groupadd|groupdel|gpasswd|chsh|visudo|chpasswd)\b'
              pat[ctl-set]='\b(timedatectl|hostnamectl|localectl)[[:space:]]+set-'

              # manifest allow-groups must be known pattern groups
              while read -r n g; do
                [[ -n ''${pat[$g]+x} ]] || { echo "manifest: $n allows unknown pattern group: $g"; bad=1; }
              done < <(jq -r '.scripts | to_entries[] | .key as $k | (.value.allow // [])[] | "\($k) \(.)"' "$manifest")

              for f in "$bin"/*; do
                [[ -f $f && -x $f ]] || continue
                name=$(basename "$f")
                # strip full-line comments: prose about Arch tools is harmless
                grep -v '^[[:space:]]*#' "$f" > scan.txt || true
                hits=""
                for g in "''${!pat[@]}"; do
                  if grep -Eq "''${pat[$g]}" scan.txt; then hits="$hits $g"; fi
                done
                hits=''${hits# }

                class=$(jq -r --arg n "$name" '.scripts[$n].class // ""' "$manifest")

                # clean = tier-1 verified user-safe (or a clean classified script)
                [[ -z $hits ]] && continue

                if [[ -z $class ]]; then
                  echo "UNCLASSIFIED mutator: $name ->$hits"
                  bad=1
                  continue
                fi

                if [[ $class == user-safe ]]; then
                  for g in $hits; do
                    if ! jq -e --arg n "$name" --arg g "$g" '.scripts[$n].allow // [] | index($g)' "$manifest" >/dev/null; then
                      echo "user-safe $name keeps undeclared pattern group: $g"
                      bad=1
                    fi
                  done
                else
                  echo "classified $class script still contains forbidden patterns: $name ->$hits"
                  bad=1
                fi
              done

              # stale manifest keys (upstream dropped a script -> revisit)
              while read -r n; do
                [[ -f $bin/$n ]] || { echo "stale manifest key (not in packaged bin): $n"; bad=1; }
              done < <(jq -r '.scripts | keys[]' "$manifest")

              # hidden menu ids must be gone
              while read -r id; do
                if grep -qF "\"$id\":" "$menu"; then echo "menu entry not hidden: $id"; bad=1; fi
              done < <(jq -r '.hiddenMenuIds[]' "$manifest")

              # menu must not reference any stubbed (declarative-note) mutator
              while read -r n; do
                if grep -qF "$n" "$menu"; then echo "menu still references stubbed mutator: $n"; bad=1; fi
              done < <(jq -r '.scripts | to_entries[] | select(.value.class == "declarative-note") | .key' "$manifest")

              [[ $bad == 0 ]] || exit 1
              touch $out
            '';

          # Transaction integrity for omarchy-nix-add / omarchy-nix-remove.
          # Runs the PACKAGED scripts against stubbed
          # sudo / nix / nixos-rebuild / fzf and asserts the acceptance
          # criteria: parallel adds keep the union, add/remove collisions
          # converge deterministically, one rebuild per batch, hash-checked
          # rollback never reverts a newer mutation, audit logs persist, and
          # the concurrency cases are repeated many times.
          omarchy-nix-transactions =
            let
              omarchyPkg = self.packages.${system}.omarchy;

              # Passthrough sudo; SUDO_CHMOD_WINDOW=1 opens a write window on
              # the (0555) flake dir so tee/mv/rm can act as root would.
              stubSudo = pkgs.writeShellScript "stub-sudo" ''
                if [[ ''${SUDO_CHMOD_WINDOW:-0} == 1 ]]; then
                  chmod -R u+w "$OMARCHY_NIX_FLAKE"
                  "$@"
                  rc=$?
                  chmod 555 "$OMARCHY_NIX_FLAKE"
                  exit "$rc"
                fi
                exec "$@"
              '';

              # Counts invocations; optionally sabotages the JSON mid-rebuild
              # (a non-cooperating writer) and fails on demand.
              stubRebuild = pkgs.writeShellScript "stub-nixos-rebuild" ''
                echo x >> "''${COUNT_FILE:?}"
                if [[ ''${REBUILD_SABOTAGE:-0} == 1 ]]; then
                  j="$OMARCHY_NIX_FLAKE/omarchy-packages.json"
                  ${pkgs.jq}/bin/jq '.packages = (((.packages // []) + ["sabotage-pkg"]) | unique)' "$j" >"$j.sabotage" \
                    && mv "$j.sabotage" "$j"
                fi
                exit "''${FAKE_REBUILD_RC:-0}"
              '';

              # Every raw nixpkgs attribute resolves (nix eval --quiet).
              # NIX_STUB_SLOW=1 makes `nix search` take 5s, to prove a slow
              # background index refresh does not hold the transaction lock.
              stubNix = pkgs.writeShellScript "stub-nix" ''
                if [[ ''${NIX_STUB_SLOW:-0} == 1 && ''${1:-} == search ]]; then
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
                echo "case i (git registration + no-op) OK"

                # --- (j) background index refresh never holds the lock ----------
                new_flake j
                NIX_STUB_SLOW=1 omarchy-nix-add install.browser.firefox >/dev/null
                lockkey=$(printf '%s' "$OMARCHY_NIX_FLAKE/omarchy-packages.json" | sha256sum | cut -d' ' -f1)
                flock -w 3 "$XDG_STATE_HOME/omarchy/nix-add/locks/$lockkey.lock" true ||
                  fail "case j: background index refresh still holds the transaction lock"
                echo "case j (no lock leak to background) OK"

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

                # --- audit logs exist and are complete for a successful op ------
                logf=$(grep -rl 'result: rebuild ok' "$XDG_STATE_HOME/omarchy/nix-add/" | head -1 || true)
                [[ -n $logf ]] || fail "no successful audit log found"
                for k in 'command:' 'ids:' 'pre-hash:' 'post-hash:' 'result:'; do
                  grep -q "$k" "$logf" || fail "audit log missing field: $k"
                done
                echo "audit log completeness OK"

                touch $out
              '';

          # One OMARCHY_NIX_FLAKE resolver for every omarchy-nix command.
          # Asserts all consumers accept the same two explicit
          # forms (flake dir / flake.nix file), canonicalize symlinks and
          # whitespace, fail CLOSED on an invalid explicit value (never fall
          # back to another checkout), and that presence checks observe the
          # same JSON that add/remove mutate.
          omarchy-flake-resolver =
            let
              omarchyPkg = self.packages.${system}.omarchy;
              # Marker-aware nix stub: answers the resolver's foreign-library
              # probe (nix eval --raw <flake>#nixosConfigurations --apply …)
              # with "host" when <flake>/.consumer exists, "foreign"
              # otherwise; everything else exits 0 so nothing real is rebuilt.
              stubNix = pkgs.writeShellScript "stub-nix" ''
                for arg in "$@"; do
                  case "$arg" in
                    *#nixosConfigurations)
                      flake=''${arg%%#*}
                      if [ -f "$flake/.consumer" ]; then echo host; else echo foreign; fi
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
              '';

          # Option-value validation + safe serialization. Three
          # layers:
          #   1. negative eval cases — rejected values must throw at
          #      evaluation time (forced via the negativeCases env var, which
          #      is evaluated when the derivation is instantiated)
          #   2. monitors.lua — luac -p syntax check + a Lua harness that
          #      stubs hl.* and asserts every field round-trips with the
          #      right type (numeric scale vs the "auto" string, transform
          #      as a number)
          #   3. environment.d — the REAL systemd user-environment generator
          #      parses the serialized file; a Python decoder reverses the
          #      generator's own escapes and asserts byte-exact values plus
          #      the exact key set (a forged key would fail the comparison).
          omarchy-option-validation =
            let
              lib = pkgs.lib;
              fmt = import ./modules/lib/omarchy-formats.nix { inherit lib; };
              schema = (import ./config.nix { inherit lib; }).omarchyOptions;

              # Evaluate just the omarchy option schema with the given
              # assignments; forcing .config.omarchy.<name> runs the module
              # system's type checks.
              omEval =
                assigns:
                (lib.evalModules {
                  modules = [
                    { options.omarchy = schema; }
                    { omarchy = assigns; }
                  ];
                }).config;

              # Assert expr FAILS evaluation (option-type rejection or a fmt
              # throw). tryEval + deepSeq catches both; a value that is
              # suddenly ACCEPTED throws here instead, failing the check.
              assertNeg =
                name: expr:
                if (builtins.tryEval (builtins.deepSeq expr expr)).success then
                  throw "omarchy-option-validation: negative case did NOT fail: ${name}"
                else
                  true;

              negativeCases = [
                (assertNeg "scale-0" (omEval { scale = 0; }).omarchy.scale)
                (assertNeg "scale-3" (omEval { scale = 3; }).omarchy.scale)
                (assertNeg "theme-traversal" (omEval { theme = "../etc"; }).omarchy.theme)
                (assertNeg "theme-newline"
                  (omEval {
                    theme = "a
b";
                  }).omarchy.theme
                )
                (assertNeg "terminal-newline"
                  (omEval {
                    terminal = "foot
kitty";
                  }).omarchy.terminal
                )
                (assertNeg "full-name-newline"
                  (omEval {
                    full_name = "A
B";
                  }).omarchy.full_name
                )
                (assertNeg "email-cr" (omEval { email_address = "a@bc"; }).omarchy.email_address)
                (assertNeg "monitor-empty-output" (fmt.parseMonitor ", 1920x1080"))
                (assertNeg "monitor-6-fields" (fmt.parseMonitor "DP-1, preferred, auto, 1, 0, extra"))
                (assertNeg "monitor-bad-scale" (fmt.parseMonitor "DP-1, preferred, auto, abc"))
                (assertNeg "monitor-bad-transform" (fmt.parseMonitor "DP-1, preferred, auto, 1, 8"))
                (assertNeg "monitorsLuaText-scale-3" (
                  fmt.monitorsLuaText {
                    scale = 3;
                    monitors = [ ];
                  }
                ))
              ];

              monitorsLua = pkgs.writeText "monitors.lua" (
                fmt.monitorsLuaText {
                  scale = 2;
                  monitors = [
                    "DP-1, 2560x1440@120, 0x0, 1.5, 2"
                    ''HDMI-"quoted"\back\name, preferred, auto, auto''
                    "tab\toutput"
                    "DP-ąęść-🎮"
                    "eDP-1"
                  ];
                }
              );

              envdConf = pkgs.writeText "50-omarchy.conf" (
                fmt.envdLines {
                  OMARCHY_USER_NAME = ''John "JD" Doe \ $HOME'';
                  OMARCHY_USER_EMAIL = "john+tag@example.com";
                }
                + "\n"
              );

              envdEmptyConf = pkgs.writeText "50-omarchy-empty.conf" (
                fmt.envdLines {
                  OMARCHY_USER_NAME = "";
                  OMARCHY_USER_EMAIL = "only-email@example.com";
                }
                + "\n"
              );

              luaHarness = pkgs.writeText "harness.lua" ''
                local captured = {}
                hl = {
                  monitor = function(t) captured[#captured + 1] = t end,
                  env = function() end,
                }
                dofile(os.getenv("MONITORS_LUA"))
                local function check(i, field, expected, want_type)
                  local v = captured[i][field]
                  assert(v ~= nil, string.format("entry %d field %s: missing", i, field))
                  assert(type(v) == want_type,
                    string.format("entry %d field %s: type %s, want %s", i, field, type(v), want_type))
                  assert(tostring(v) == expected,
                    string.format("entry %d field %s: got %q want %q", i, field, tostring(v), expected))
                end
                -- entry 1 is the catch-all; scale=2 -> omarchy_monitor_scale = "1.2"
                assert(captured[1].output == "", "catch-all output must be empty")
                assert(captured[1].scale == "1.2",
                  "catch-all scale must be 1.2, got " .. tostring(captured[1].scale))
                check(2, "output", "DP-1", "string")
                check(2, "mode", "2560x1440@120", "string")
                check(2, "position", "0x0", "string")
                check(2, "scale", "1.5", "number")
                check(2, "transform", "2", "number")
                check(3, "output", os.getenv("EXP3_OUTPUT"), "string")
                check(3, "scale", "auto", "string") -- "auto" must stay a string
                check(4, "output", os.getenv("EXP4_OUTPUT"), "string")
                check(5, "output", os.getenv("EXP5_OUTPUT"), "string")
                check(6, "output", "eDP-1", "string")
                assert(captured[6].mode == nil, "eDP-1 must have no mode")
                assert(#captured == 6, "expected 6 hl.monitor calls, got " .. #captured)
                print("lua harness OK")
              '';

              # Reverse the generator's own output escapes and compare
              # byte-exact; the whole-dict comparison also proves no key was
              # injected beyond PATH (which the generator always prints).
              envdDecode = pkgs.writeText "envd-decode.py" ''
                import os, sys

                def decode(val):
                    # Generator serializer escapes (inside quotes):
                    # \\ -> \, \$ -> $, \" -> ", \n -> NL, \t -> TAB
                    mapping = {'\\': '\\', '$': '$', '"': '"', 'n': '\n', 't': '\t'}
                    out = []
                    i = 0
                    while i < len(val):
                        if val[i] == '\\' and i + 1 < len(val) and val[i + 1] in mapping:
                            out.append(mapping[val[i + 1]])
                            i += 2
                        else:
                            out.append(val[i])
                            i += 1
                    return '''.join(out)

                expected = {
                    'OMARCHY_USER_NAME': os.environ['EXP_NAME'],
                    'OMARCHY_USER_EMAIL': 'john+tag@example.com',
                }
                seen = {}
                with open('gen.out') as fh:
                    for line in fh:
                        line = line.rstrip('\n')
                        if '=' not in line:
                            continue
                        k, v = line.split('=', 1)
                        if k == 'PATH':
                            continue
                        if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                            v = decode(v[1:-1])
                        seen[k] = v

                if seen != expected:
                    sys.stderr.write(f"envd mismatch:\nseen     = {seen!r}\nexpected = {expected!r}\n")
                    sys.exit(1)
                print("envd round-trip OK")
              '';
            in
            pkgs.runCommand "omarchy-option-validation-check"
              {
                nativeBuildInputs = [
                  pkgs.lua5_4
                  pkgs.python3
                ];
                # Forcing this env var at instantiation time evaluates every
                # negative case: a regression throws during EVAL, before the
                # builder even runs.
                negativeCases = lib.concatStringsSep "," (map toString negativeCases);
              }
              ''
                set -euo pipefail
                fail() { echo "FAIL: $*" >&2; exit 1; }

                # --- monitors.lua: syntax + semantics -----------------------
                luac -p ${monitorsLua} || fail "luac -p rejected monitors.lua"
                export MONITORS_LUA=${monitorsLua}
                export EXP3_OUTPUT='HDMI-"quoted"\back\name'
                export EXP4_OUTPUT=$'tab\toutput'
                export EXP5_OUTPUT='DP-ąęść-🎮'
                lua ${luaHarness} || fail "lua harness"

                # --- environment.d: real systemd generator round-trip -------
                GENERATOR="${pkgs.systemd}/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
                export HOME=$TMPDIR/home
                mkdir -p "$HOME/.config/environment.d"
                # cp -f: store sources are read-only, so a plain second cp
                # cannot overwrite the first copy.
                cp -f ${envdConf} "$HOME/.config/environment.d/50-omarchy.conf"
                "$GENERATOR" > gen.out 2> gen.err
                ! grep -q "invalid syntax" gen.err || { cat gen.err; fail "generator rejected 50-omarchy.conf"; }
                EXP_NAME='John "JD" Doe \ $HOME' python3 ${envdDecode} || fail "envd round-trip"

                # --- empty values are omitted, file still parses clean ------
                cp -f ${envdEmptyConf} "$HOME/.config/environment.d/50-omarchy.conf"
                "$GENERATOR" > gen2.out 2> gen2.err
                ! grep -q "invalid syntax" gen2.err || { cat gen2.err; fail "generator rejected empty-name conf"; }
                grep -q '^OMARCHY_USER_EMAIL=only-email@example.com$' gen2.out ||
                  fail "email missing from empty-name run: $(cat gen2.out)"
                ! grep -q 'OMARCHY_USER_NAME' gen2.out ||
                  fail "empty OMARCHY_USER_NAME must be omitted"

                touch $out
              '';

          # Documentation coverage for the public option surface:
          # every option declared in config.nix must have a
          # `### `omarchy.<path>` heading in docs/options.md, and every such
          # heading must name a real declared option (no stale docs). Both
          # directions are compared as sorted sets so a missing OR orphaned
          # entry fails the build with the diff.
          omarchy-options-documented =
            let
              lib = pkgs.lib;
              schema = (import ./config.nix { inherit lib; }).omarchyOptions;
              # Collect leaf option paths ("enable", "autologin.user", ...).
              # mkOption values are attrsets too, so test lib.isOption BEFORE
              # recursing.
              optionPaths =
                let
                  go =
                    prefix: attrs:
                    lib.concatLists (
                      lib.mapAttrsToList (
                        name: value:
                        if lib.isOption value then
                          [ (lib.concatStringsSep "." (prefix ++ [ name ])) ]
                        else if builtins.isAttrs value then
                          go (prefix ++ [ name ]) value
                        else
                          [ ]
                      ) attrs
                    );
                in
                go [ ] schema;
              declaredFile = pkgs.writeText "omarchy-options-declared" (
                lib.concatStringsSep "\n" (lib.sort (a: b: a < b) optionPaths) + "\n"
              );
            in
            pkgs.runCommand "omarchy-options-documented-check" { } ''
              set -euo pipefail
              # Headings look like: ### `omarchy.full_name` *(...)* — extract
              # the bare option path, sort, and diff against the declared set.
              grep -o '^### `omarchy\.[A-Za-z0-9._]*`' ${./docs/options.md} |
                sed 's/^### `omarchy\.//; s/`$//' | LC_ALL=C sort > documented.txt
              if ! diff -u ${declaredFile} documented.txt; then
                echo "FAIL: docs/options.md headings diverge from config.nix declarations" >&2
                echo "(< declared but undocumented, > documented but not declared)" >&2
                exit 1
              fi
              touch $out
            '';
          # Package contract for the vendored Fish profile:
          # every installed .fish file parses, the vendor dirs are populated
          # (including leading-dot functions), fzf.fish v10.3 is bundled, the
          # Quattro bash-parity helpers ship (fork pin carrying PR
          # omacom-io/omarchy-fish#7), try.fish carries the lazy `try init`
          # integration, and no active file references Arch-only paths or
          # pacman.
          omarchy-fish-package =
            let
              fishPkg = self.packages.${system}.omarchy-fish;
            in
            pkgs.runCommand "omarchy-fish-package-check" { nativeBuildInputs = [ pkgs.fish ]; } ''
              set -euo pipefail
              fail() { echo "FAIL: $*" >&2; exit 1; }

              cd ${fishPkg}

              # Every installed fish file parses.
              find share/fish -name '*.fish' -print0 |
                while IFS= read -r -d "" f; do
                  fish -n "$f" || fail "fish -n: $f"
                done

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

              # Quattro bash-parity helpers (PR omacom-io/omarchy-fish#7,
              # currently via the fork pin — see pkgs/omarchy-fish.nix).
              for fn in cy mup rsw lsw dsw tds; do
                [ -e "share/fish/vendor_functions.d/$fn.fish" ] ||
                  fail "missing $fn.fish (bash-parity helper)"
              done

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
            '';
          # Bash/fish parity guard: every helper the pinned Quattro bash
          # profile defines (aliases + functions in default/bash/aliases and
          # default/bash/fns/*) must have a fish counterpart in the vendored
          # profile (a vendor_functions.d file or a function defined in
          # vendor_conf.d). A NEW upstream bash helper fails this check at
          # bump time until fish gains it or it is consciously allowlisted
          # in expectedMissing below — see
          # docs/decisions/2026-07-31-fish-parity-fork-pin.md.
          omarchy-fish-parity =
            let
              fishPkg = self.packages.${system}.omarchy-fish;
              omarchyPkg = self.packages.${system}.omarchy;
              # Intentional omissions (bash helper -> why fish needs none):
              #   "..": omarchy-fish ships "..." and "...." but no "..", and
              #     fish itself has no builtin ".." — upstream fish-profile
              #     gap, not a port deviation. Remove from this list if
              #     omarchy-fish ever adds ...fish (the ".." function file).
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
            '';
          # Fish wiring: with omarchy.fish.enable = true the module
          # sets programs.fish.enable and puts the vendored profile in the
          # system profile; the default (off) adds neither (demo config is the
          # off witness). Same eval-time assertion pattern as the disabled-state
          # module check.
          omarchy-fish-module =
            let
              fishPkg = self.packages.${system}.omarchy-fish;
              mkEval =
                extra:
                nixpkgs.lib.nixosSystem {
                  # Same pinned pkgs instance the other module checks use —
                  # carries the scoped unfree predicate the omarchy default
                  # app set needs at eval (obsidian). `inherit system` instead
                  # would re-import nixpkgs without it and fail on unfree.
                  inherit pkgs;
                  modules = [
                    self.nixosModules.default
                    {
                      omarchy.enable = true;
                      omarchy.fish.enable = true;
                      fileSystems."/".device = "/dev/null";
                      fileSystems."/".fsType = "ext4";
                      boot.loader.grub.device = "nodev";
                      system.stateVersion = "26.05";
                    }
                    extra
                  ];
                };
              cfg = (mkEval { }).config;
              # Consumer overrides EDITOR only: the SUDO_EDITOR indirection
              # must stay intact so pam_env expands the override at login
              # (upstream's SUDO_EDITOR="$EDITOR" semantics).
              editorCfg = (mkEval { environment.sessionVariables.EDITOR = "nvim"; }).config;
              pamEnv = cfg.environment.etc."pam/environment".source;
              hasFish = builtins.any (p: (p.drvPath or "") == fishPkg.drvPath) cfg.environment.systemPackages;
            in
            if !cfg.programs.fish.enable then
              throw "omarchy.fish.enable did not set programs.fish.enable"
            else if !hasFish then
              throw "omarchy-fish package missing from environment.systemPackages"
            else if self.nixosConfigurations.demo.config.programs.fish.enable then
              throw "fish must default to off — demo config has programs.fish.enable"
            else if cfg.environment.sessionVariables.SUDO_EDITOR != "\${EDITOR}" then
              throw "SUDO_EDITOR must carry the pam_env \${EDITOR} indirection"
            else if editorCfg.environment.sessionVariables.SUDO_EDITOR != "\${EDITOR}" then
              throw "SUDO_EDITOR indirection must survive an EDITOR override"
            else if cfg.system.build.toplevel.drvPath == null then
              throw "unreachable" # forces full evaluation incl. assertions
            else
              pkgs.runCommand "omarchy-fish-module-check" { } ''
                # pam_env expands ''${EDITOR} at login in file order — the
                # EDITOR line must precede the SUDO_EDITOR line, and the
                # indirection must survive the renderer verbatim.
                ed=$(grep -n '^EDITOR[[:space:]]' ${pamEnv} | cut -d: -f1)
                se=$(grep -n '^SUDO_EDITOR[[:space:]]' ${pamEnv} | cut -d: -f1)
                [ -n "$ed" ] && [ -n "$se" ] || { echo "EDITOR/SUDO_EDITOR missing in pam/environment"; exit 1; }
                [ "$ed" -lt "$se" ] || { echo "EDITOR line must precede SUDO_EDITOR in pam/environment"; exit 1; }
                grep -q '^SUDO_EDITOR[[:space:]]*DEFAULT="''${EDITOR}"$' ${pamEnv} || {
                  echo "SUDO_EDITOR lost the ''${EDITOR} indirection in pam/environment"; exit 1; }
                touch $out
              '';
        }
      );

      nixosConfigurations = {
        # Minimal NixOS config that consumes the omarchy NixOS + Home-Manager
        # modules with `enable = true`. Used as the Stage 3/4 verification
        # vehicle (build the toplevel / a VM) and as a reference for consumers.
        # Not a substitute for example/configuration.nix, which Stage 5 wires
        # into a full desktop build.
        demo =
          let
            pkgs = pkgsFor "x86_64-linux";
          in
          nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              self.nixosModules.default
              inputs.home-manager.nixosModules.home-manager
              {
                omarchy.enable = true;
                omarchy.managedPackagesFile = null; # hermetic check (host /etc must not leak in)
                omarchy.full_name = "Omarchy Demo";
                omarchy.email_address = "demo@omarchy-nix.invalid";

                # Minimal VM-friendly base so the config builds standalone. The
                # filesystem is the QEMU virtio disk; SDDM runs under its own
                # wayland greeter (omarchy leaves the default SDDM, so we need
                # wayland.enable rather than a full xserver).
                fileSystems."/".device = "/dev/disk/by-label/nixos";
                fileSystems."/".fsType = "ext4";
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
                services.openssh.enable = true;
                services.displayManager.sddm.wayland.enable = true;
                users.users.demo = {
                  isNormalUser = true;
                  extraGroups = [
                    "wheel"
                    "video"
                    "input"
                  ];
                  initialPassword = "demo";
                };

                # Home-Manager seeds the per-user config (Hyprland Lua entry
                # point + user stubs + theme symlink). omarchy.enable is set
                # explicitly in HM (the module reads omarchy.* values from
                # osConfig.omarchy with a fallback to HM-local options, but does
                # not mirror enable itself to avoid an evaluation cycle).
                home-manager.users.demo = {
                  imports = [ self.homeManagerModules.default ];
                  home.username = "demo";
                  home.homeDirectory = "/home/demo";
                  home.stateVersion = "26.05";
                  omarchy.enable = true;
                };

                virtualisation.vmVariant = {
                  virtualisation.memorySize = 4096;
                  virtualisation.cores = 8;
                };
                system.stateVersion = "26.05";
              }
            ];
          };

        # Reference consumer config (example/configuration.nix) wired exactly the
        # way README + docs/install.md show. Deliberately uses nixosSystem's OWN
        # nixpkgs instance (no pkgsFor / allowUnfree): `nix flake check`
        # evaluates it like an external consumer on a default nixpkgs config, so
        # a consumer-side eval break (e.g. an unfree default app) fails here
        # instead of at the user's first build.
        example = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./example/configuration.nix
            self.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [ self.homeManagerModules.default ];
            }
          ];
        };
      }
      # Optional extra nixosConfigurations, spliced in only when the file
      # exists.
      // nixpkgs.lib.optionalAttrs (builtins.pathExists ./hosts/dev-configurations.nix) (
        import ./hosts/dev-configurations.nix {
          inherit
            inputs
            self
            nixpkgs
            pkgsFor
            ;
        }
      );
    };
}
