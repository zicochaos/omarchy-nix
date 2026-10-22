# Keep the historical check name, and cover the other scripted user units
# too: NixOS gives these units a sparse PATH rather than the login shell's.
# The required commands come from their vendored entry points and helpers.
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  lib = nixpkgs.lib;
  services = self.nixosConfigurations.demo.config.systemd.user.services;
  shellCommands = [
    "omarchy-shell"
    "qs"
    "socat"
  ];
  required = {
    omarchy-sleep-lock = shellCommands ++ [
      "jq"
      "hyprctl"
      "omarchy-notification-send"
      "omarchy-hyprland-monitor-clamshell"
    ];
    owed = shellCommands ++ [
      "jq"
      "hyprctl"
      "omarchy-theme-bg-boot-intro"
    ];
    omarchy-migrate = shellCommands ++ [
      "jq"
      "awk"
      "gsettings"
    ];
    omarchy-migrate-notify = shellCommands ++ [
      "jq"
      "flock"
      "busctl"
      "omarchy-migrate"
      "omarchy-notification-wait"
      "omarchy-notification-send"
    ];
    omarchy-crash-watch = shellCommands ++ [
      "jq"
      "journalctl"
      "busctl"
      "omarchy-notification-wait"
      "omarchy-default-agent"
    ];
    omarchy-recover-internal-monitor = [ "omarchy-hw-external-monitors" ];
    omarchy-tailscale-receive = [
      "tailscale"
      "jq"
      "busctl"
      "omarchy-notification-send"
      "omarchy-i18n"
    ];
  };
  probes = lib.mapAttrsToList (unit: commands: ''
    export PATH=${lib.escapeShellArg (lib.makeBinPath services.${unit}.path)}
    for cmd in ${lib.concatStringsSep " " commands}; do
      if ! command -v "$cmd" >/dev/null; then
        echo "${unit} PATH missing $cmd" >&2
        missing=1
      fi
    done
  '') required;
in
pkgs.runCommand "omarchy-sleep-lock-path" { } ''
  builderPath=$PATH
  missing=0
  ${lib.concatStringsSep "\n" probes}
  [[ $missing == 0 ]] || exit 1
  export PATH=$builderPath
  touch $out
''
