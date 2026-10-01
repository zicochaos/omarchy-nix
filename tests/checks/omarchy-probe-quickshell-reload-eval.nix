# tests/probe-quickshell-reload.nix is a manual probe, not a VM check, so
# nothing evaluated it and it broke twice unnoticed (96e8279: a node
# merge silently dropped omarchy.enable on the override path; a5446ff:
# the documented invocation stopped evaluating). Evaluate it the way its
# header documents, for the pinned build and for an override, without
# building or booting anything: force each test driver's drvPath and
# assert the node keeps the desktop on and runs the build under test.
{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
let
  inherit (pkgs) lib;
  probe =
    qsOverride:
    pkgs.testers.nixosTest (
      import ../probe-quickshell-reload.nix {
        inherit pkgs lib qsOverride;
        omarchy = self;
        home-manager = inputs.home-manager;
      }
    );
  variants = {
    pinned = {
      test = probe null;
      expected = self.packages.${system}.quickshell;
    };
    # nixpkgs' own quickshell stands in for "another build".
    override = {
      test = probe (p: p.quickshell);
      expected = pkgs.quickshell;
    };
  };
  checkVariant =
    name: v:
    let
      node = v.test.nodes.machine;
    in
    assert lib.assertMsg node.omarchy.enable "probe (${name}): omarchy.enable is off on the probe node";
    assert lib.assertMsg (
      node.omarchy.quickshellPackage.drvPath == v.expected.drvPath
    ) "probe (${name}): the node does not run the quickshell build under test";
    # Discard the context: the driver must be instantiated (that is the
    # check) but not become a build input of this derivation.
    "${name}: ${builtins.unsafeDiscardStringContext v.test.driver.drvPath}";
in
pkgs.runCommand "omarchy-probe-quickshell-reload-eval" { } ''
  printf 'probe driver instantiated, %s\n' ${lib.escapeShellArgs (lib.mapAttrsToList checkVariant variants)}
  touch $out
''
