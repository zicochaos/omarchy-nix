# Documentation coverage for the public option surface:
# every option declared in config.nix must have a
# `### `omarchy.<path>` heading in docs/options.md, and every such
# heading must name a real declared option (no stale docs). Both
# directions are compared as sorted sets so a missing OR orphaned
# entry fails the build with the diff.
{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  schema = (import ../../config.nix { inherit lib; }).omarchyOptions;
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
  grep -o '^### `omarchy\.[A-Za-z0-9._]*`' ${../../docs/options.md} |
    sed 's/^### `omarchy\.//; s/`$//' | LC_ALL=C sort > documented.txt
  if ! diff -u ${declaredFile} documented.txt; then
    echo "FAIL: docs/options.md headings diverge from config.nix declarations" >&2
    echo "(< declared but undocumented, > documented but not declared)" >&2
    exit 1
  fi
  touch $out
''
