# omarchy-sleep-lock holds a delay inhibitor, then execs
# omarchy-system-sleep-lock, which talks to the running shell via
# bare `omarchy-shell` / `qs` / `jq`. User-unit PATH is sparse;
# missing those binaries means the lock request never lands and
# the machine suspends unlocked.
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  pathPkgs = self.nixosConfigurations.demo.config.systemd.user.services.omarchy-sleep-lock.path;
  pathValue = nixpkgs.lib.makeBinPath pathPkgs;
  required = [
    "omarchy-shell"
    "qs"
    "jq"
    "hyprctl"
    "omarchy-notification-send"
    "omarchy-hyprland-monitor-clamshell"
  ];
in
pkgs.runCommand "omarchy-sleep-lock-path" { } ''
  export PATH=${nixpkgs.lib.escapeShellArg pathValue}
  missing=0
  for cmd in ${nixpkgs.lib.concatStringsSep " " required}; do
    if ! command -v "$cmd" >/dev/null; then
      echo "omarchy-sleep-lock PATH missing $cmd" >&2
      missing=1
    fi
  done
  if [ "$missing" != 0 ]; then
    echo "PATH was: $PATH" >&2
    exit 1
  fi
  touch $out
''
