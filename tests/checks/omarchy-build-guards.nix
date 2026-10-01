# The vendoring derivation's fail-closed guards: build pkgs/omarchy.nix
# from an upstream tree with one deliberate change and require the build
# to FAIL with the guard's message — an upstream rename must stop the
# build instead of shipping an orphan replacement or an unpinned
# interpreter. Covers a hand-written overwrite (overwrite_upstream), a
# manifest-generated declarative-note stub, and the bash -p interpreter
# pin of the command-scoped sudo entrypoints.
{
  self,
  pkgs,
  system,
  ...
}:
let
  inherit (pkgs) lib;
  omarchyPkg = self.packages.${system}.omarchy;
  expectGuard =
    name: mutate: message:
    let
      src = pkgs.runCommand "omarchy-src-${name}" { } ''
        cp -r ${omarchyPkg.src} $out
        chmod -R u+w $out
        cd $out
        ${mutate}
      '';
      failed = pkgs.testers.testBuildFailure (omarchyPkg.override { omarchy-src = src; });
    in
    pkgs.runCommand "omarchy-build-guard-${name}" { } ''
      if ! grep -qF ${lib.escapeShellArg message} ${failed}/testBuildFailure.log; then
        echo "${name}: the build failed, but not with: ${message}"
        tail -20 ${failed}/testBuildFailure.log
        exit 1
      fi
      touch $out
    '';
  cases = [
    (expectGuard "overwrite" "rm bin/omarchy-version"
      "overwrite target missing (upstream rename?): bin/omarchy-version"
    )
    (expectGuard "generated-stub" "rm bin/omarchy-dns"
      "overwrite target missing (upstream rename?): bin/omarchy-dns"
    )
    (expectGuard "interpreter-pin"
      "sed -i '1s|.*|#!/usr/bin/env -S bash -p|' bin/omarchy-update-stay-awake"
      "interpreter pin did not apply (upstream shebang changed?): bin/omarchy-update-stay-awake"
    )
  ];
in
pkgs.runCommand "omarchy-build-guards-check" { inherit cases; } ''
  touch $out
''
