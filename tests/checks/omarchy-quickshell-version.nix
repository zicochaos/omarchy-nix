# The desktop runs this repo's quickshell pin (pkgs/quickshell.nix)
# rather than the consumer's pkgs.quickshell: stable nixpkgs carries
# 0.3.0, and 0.3.1 fixes the plugin-reload OSD side effect this port
# measured (plus crash fixes). Run the binary so a silently
# unapplied override (or a nixpkgs recipe change) cannot pass, and
# check the shell's IPC entry point exists for the sleep-lock unit.
{
  self,
  pkgs,
  system,
  ...
}:
let
  qs = self.packages.${system}.quickshell;
in
pkgs.runCommand "omarchy-quickshell-version" { } ''
  set -euo pipefail
  # Output: "Quickshell 0.3.1 (revision tag-v0.3.1, distributed by ...)".
  # Compare the version field exactly: a substring match on 0.3.1 would
  # also accept 0.3.10 or 0.3.1-rc.
  version="$(QT_QPA_PLATFORM=offscreen ${qs}/bin/quickshell --version 2>&1)"
  read -r name number _ <<<"$version"
  if [ "$name" != Quickshell ] || [ "$number" != 0.3.1 ]; then
    echo "quickshell pin is not 0.3.1: $version" >&2
    exit 1
  fi
  test -x ${qs}/bin/qs || {
    echo "quickshell package lost the qs IPC binary" >&2
    exit 1
  }
  touch $out
''
