# omarchy-nix-add writes raw nixpkgs attribute *paths* (including
# nested ones like kdePackages.dolphin) into omarchy-packages.json.
# The module must resolve dotted paths the same way catalog probes
# do (lib.attrByPath), not pkgs.${n} (a single top-level attr named
# with a literal dot). Regression: add + rebuild used to fail with
# "unknown nixpkgs attribute 'kdePackages.dolphin'" even though
# pkgs.kdePackages.dolphin exists.
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  # Real fixture files, not builtins.toFile: the module reads the
  # path with builtins.pathExists, and --no-build evaluation cannot
  # realise a toFile path that a GC removed (it fails with
  # "path ... is not valid"). Files inside the flake source always
  # exist, so `nix flake check --no-build` stays GC-safe.
  mkEval =
    file:
    nixpkgs.lib.nixosSystem {
      inherit pkgs;
      modules = [
        self.nixosModules.default
        {
          omarchy.enable = true;
          omarchy.managedPackagesFile = file;
          fileSystems."/".device = "/dev/null";
          fileSystems."/".fsType = "ext4";
          boot.loader.grub.device = "nodev";
          system.stateVersion = "26.05";
        }
      ];
    };
  pkgIn =
    needle: cfg: builtins.any (p: (p.drvPath or "") == needle.drvPath) cfg.environment.systemPackages;
  goodFile = ../fixtures/managed-packages-nested.json;
  good = (mkEval goodFile).config;

  # A rejected name must fail exactly where the module resolves it, not
  # anywhere in the evaluation. The list type's merge forces every element
  # while building config.environment.systemPackages, so isolate at the
  # raw definitions instead: exactly one element fails, in the module's
  # managed-packages definition (one entry per JSON name), and the name
  # really is absent (no nixpkgs path, no flake-owned package) — the
  # module's unknown-attribute throw is the only way that entry can fail.
  # (tryEval cannot see the message, and the module needs the flake's
  # inputs, so the eval cannot run in a build sandbox to grep it.)
  managedCount = file: builtins.length (builtins.fromJSON (builtins.readFile file)).packages;
  failingIn = def: builtins.filter (el: !(builtins.tryEval (builtins.seq el true)).success) def.value;
  failingDefs =
    file:
    builtins.filter (def: failingIn def != [ ])
      (mkEval file).options.environment.systemPackages.definitionsWithLocations;
  rejectedAlone =
    file: path:
    let
      cfg = (mkEval file).config;
      bad = failingDefs file;
      def = builtins.head bad;
    in
    builtins.length bad == 1
    && pkgs.lib.hasSuffix "modules/nixos/default.nix" (toString def.file)
    && builtins.length def.value == managedCount file
    && builtins.length (failingIn def) == 1
    && !(builtins.tryEval (builtins.length cfg.environment.systemPackages)).success
    && pkgs.lib.hasAttrByPath (pkgs.lib.init path) pkgs
    && !(pkgs.lib.hasAttrByPath path pkgs)
    && !(cfg.omarchy.ownedPackages ? ${pkgs.lib.concatStringsSep "." path});
in
if !(pkgIn pkgs.hello good) then
  throw "top-level managed attr 'hello' missing from environment.systemPackages"
else if !(pkgIn pkgs.kdePackages.dolphin good) then
  throw "nested managed attr 'kdePackages.dolphin' missing from environment.systemPackages"
else if failingDefs goodFile != [ ] then
  throw "the good managed-packages fixture has systemPackages entries that fail to evaluate"
else if
  !(rejectedAlone ../fixtures/managed-packages-nested-missing.json [
    "kdePackages"
    "definitely-not-a-real-pkg-xyz"
  ])
then
  throw "unknown nested attr kdePackages.definitely-not-a-real-pkg-xyz must fail exactly its own systemPackages entry"
else if
  !(rejectedAlone ../fixtures/managed-packages-top-missing.json [ "definitely-not-a-real-attr-xyz" ])
then
  throw "unknown top-level attr definitely-not-a-real-attr-xyz must fail exactly its own systemPackages entry"
else
  pkgs.runCommand "omarchy-managed-nested-attrs" { } "touch $out"
