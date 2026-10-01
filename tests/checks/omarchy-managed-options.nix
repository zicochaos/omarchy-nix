# Menu-set NixOS options: the omarchy-options.nix loader written by
# omarchy-nix-add (golden: optLoaderGolden) must fold
# omarchy-options.json picks into a real NixOS evaluation — next to
# our own module, which must stay import-clean alongside it.
# Evaluated at check-EVAL time (assertions are the derivation's
# env, like option-validation's negativeCases). Covers: bool/list
# folds, the empty-picks no-op, and the honest-conflict contract
# (a menu value colliding with the consumer's own config is an
# eval error, never a silent override).
#
# The fixtures are directories in the flake source (the loader reads
# ./omarchy-options.json next to itself), so evaluating them needs no
# import-from-derivation. Their loader copies are pinned byte for byte
# to the golden here, and omarchy-nix-transactions pins the golden to
# omarchy-nix-add's template: the loader evaluated is the generated one.
{
  self,
  pkgs,
  optLoaderGolden,
  ...
}:
let
  inherit (pkgs) lib;
  picks = ../fixtures/managed-options/picks;
  empty = ../fixtures/managed-options/empty;
  loaderOf = dir: dir + "/omarchy-options.nix";
  evalWith =
    dir: extraModules:
    import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        { omarchy.enable = true; }
        (loaderOf dir)
      ]
      ++ extraModules;
    };
  ev = evalWith picks [ ];
  evEmpty = evalWith empty [ ];
  # picks also sets networking.hostName = "menu-set"
  evConflict = evalWith picks [ { networking.hostName = "flake-set"; } ];

  # The conflict must be exactly the loader's pick against the consumer's
  # value, and merging those two definitions must be what fails (not some
  # other evaluation error): tryEval cannot see the message, so pin the
  # cause structurally here; the builder below checks the message text.
  hostOpt = evConflict.options.networking.hostName;
  hostDefs = hostOpt.definitionsWithLocations;
  loaderDefs = builtins.filter (
    d:
    d.value == "menu-set" && lib.hasSuffix "managed-options/picks/omarchy-options.nix" (toString d.file)
  ) hostDefs;
  merges =
    defs: (builtins.tryEval (builtins.deepSeq (hostOpt.type.merge hostOpt.loc defs) true)).success;

  assertions = [
    (lib.assertMsg (
      builtins.readFile (loaderOf picks) == optLoaderGolden.text
      && builtins.readFile (loaderOf empty) == optLoaderGolden.text
    ) "omarchy-managed-options: a fixture loader differs from the golden template")
    (lib.assertMsg ev.config.services.tailscale.enable "omarchy-managed-options: bool option not folded into config")
    (lib.assertMsg (
      ev.config.services.tailscale.extraSetFlags == [ "--accept-dns=false" ]
    ) "omarchy-managed-options: list option not folded into config")
    (lib.assertMsg (
      !evEmpty.config.services.tailscale.enable
    ) "omarchy-managed-options: empty picks must not set options")
    (lib.assertMsg (
      lib.sort lib.lessThan (map (d: d.value) hostDefs) == [
        "flake-set"
        "menu-set"
      ]
      && builtins.length loaderDefs == 1
    ) "omarchy-managed-options: the conflict is not the loader's pick against the consumer's value")
    (lib.assertMsg (!(merges hostDefs) && merges loaderDefs)
      "omarchy-managed-options: merging the pick with the consumer's value did not fail (or the pick alone did)"
    )
    (lib.assertMsg (
      !(builtins.tryEval (builtins.deepSeq evConflict.config.networking.hostName true)).success
    ) "omarchy-managed-options: menu value silently overrode the consumer's own config")
  ];
in
pkgs.runCommand "omarchy-managed-options-check"
  {
    assertions = builtins.deepSeq assertions "ok";
    nativeBuildInputs = [ pkgs.nix ];
  }
  ''
    # The conflict's message, from the same generated loader in a plain
    # module-system evaluation (a full NixOS eval needs store writes the
    # sandbox cannot do): it must name the option and attribute the pick
    # to the loader file.
    mkdir picks
    cp ${optLoaderGolden} picks/omarchy-options.nix
    echo '{"networking.hostName":"menu-set"}' >picks/omarchy-options.json
    export HOME=$TMPDIR NIX_STATE_DIR=$TMPDIR/nix-state NIX_LOG_DIR=$TMPDIR/nix-log NIX_CONF_DIR=$TMPDIR
    if nix-instantiate --eval --strict --store dummy:// -E '
      let lib = import ${pkgs.path}/lib; in
      (lib.evalModules {
        modules = [
          { options.networking.hostName = lib.mkOption { type = lib.types.str; }; }
          ./picks/omarchy-options.nix
          { networking.hostName = "flake-set"; }
        ];
      }).config.networking.hostName' 2>err.txt; then
      echo "a menu pick silently overrode the consumer's value"
      exit 1
    fi
    for want in \
      "The option \`networking.hostName' has conflicting definition values" \
      "/picks/omarchy-options.nix': \"menu-set\"" \
      ': "flake-set"'; do
      grep -qF -- "$want" err.txt || { echo "conflict message lacks: $want"; cat err.txt; exit 1; }
    done
    touch $out
  ''
