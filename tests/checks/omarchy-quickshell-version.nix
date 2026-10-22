# The desktop runs this repo's quickshell pin (pkgs/quickshell.nix)
# rather than the consumer's pkgs.quickshell: stable nixpkgs carries
# 0.3.0; 0.3.1 fixed the plugin-reload OSD side effect this port
# measured, and Omarchy 3c7027d uses snapshot 2b4501a with OmarchyLoadPatch.
# Run the binary and check its full revision so a tag-v0.3.2 build or a
# silently unapplied override cannot pass. Check the qs IPC entry point
# used by the shell and sleep-lock unit, too.
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
  # The snapshot's CMake project version stays 0.3.2. Its full source
  # revision distinguishes the requested snapshot from the release tag.
  version="$(QT_QPA_PLATFORM=offscreen ${qs}/bin/quickshell --version 2>&1)"
  expected="Quickshell 0.3.2 (revision 2b4501a282689792b62e94f3fb30d8f512324fe6, distributed by "
  if [[ "$version" != "$expected"* ]]; then
    echo "quickshell pin is not the requested 2b4501a snapshot: $version" >&2
    exit 1
  fi
  test -x ${qs}/bin/qs || {
    echo "quickshell package lost the qs IPC binary" >&2
    exit 1
  }
  QT_QPA_PLATFORM=offscreen ${qs}/bin/qs ipc --help >/dev/null
  touch $out
''
