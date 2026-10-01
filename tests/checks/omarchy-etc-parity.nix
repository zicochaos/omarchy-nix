# /etc overlay parity: upstream's Arch etc/ tree (classified in
# pkgs/omarchy-etc-manifest.nix) must match the manifest exactly
# (fail-closed both directions: a new or removed upstream file
# turns this check red until classified), and every adaptation
# must actually reach the demo system (eval assertions + greps on
# the generated files).
{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
let
  demoCfg = self.nixosConfigurations.demo.config;
  omarchyPkg = self.packages.${system}.omarchy;
  manifest = import ../../pkgs/omarchy-etc-manifest.nix;
  manifestKeys = builtins.sort (a: b: a < b) (builtins.attrNames manifest);
  allowedClasses = [
    "native"
    "vendored"
    "seed"
    "covered"
    "na"
  ];
  badClasses = builtins.filter (c: !(builtins.elem c allowedClasses)) (builtins.attrValues manifest);
  sysctl = demoCfg.boot.kernel.sysctl;
  inherit (pkgs.lib) hasInfix;
  logindConf = demoCfg.environment.etc."systemd/logind.conf".text;
  userConf = demoCfg.environment.etc."systemd/user.conf".text;
  hasSudoCmd =
    cmd:
    builtins.any (r: builtins.any (c: c.command == cmd) r.commands) demoCfg.security.sudo.extraRules;
in
if badClasses != [ ] then
  throw "omarchy-etc-manifest.nix has unknown classes: ${toString badClasses}"
else if sysctl."vm.swappiness" != 150 then
  throw "demo config missing vm.swappiness=150 (etc/sysctl.d/99-omarchy-sysctl.conf)"
else if sysctl."vm.page-cluster" != 0 then
  throw "demo config missing vm.page-cluster=0 (etc/sysctl.d/99-omarchy-sysctl.conf)"
else if sysctl."vm.dirty_bytes" != 268435456 then
  throw "demo config missing vm.dirty_bytes (etc/sysctl.d/99-omarchy-sysctl.conf)"
else if sysctl."net.ipv4.tcp_mtu_probing" != 1 then
  throw "demo config missing net.ipv4.tcp_mtu_probing=1 (etc/sysctl.d/99-omarchy-sysctl.conf)"
else if sysctl."net.ipv4.tcp_congestion_control" != "bbr" then
  throw "demo config missing net.ipv4.tcp_congestion_control=bbr (etc/sysctl.d/99-omarchy-sysctl.conf, 2026-09-13)"
else if sysctl."net.core.default_qdisc" != "fq" then
  throw "demo config missing net.core.default_qdisc=fq (etc/sysctl.d/99-omarchy-sysctl.conf, 2026-09-13)"
else if sysctl."fs.inotify.max_user_watches" != 524288 then
  throw "demo config lost fs.inotify.max_user_watches=524288 (nixpkgs sysctl.nix default changed)"
else if !(hasInfix "HandlePowerKey=ignore" logindConf) then
  throw "demo config logind.conf missing HandlePowerKey=ignore (etc/systemd/logind.conf.d/10-ignore-power-button.conf)"
else if demoCfg.systemd.settings.Manager.DefaultTimeoutStopSec != "5s" then
  throw "demo config missing DefaultTimeoutStopSec=5s (etc/systemd/system.conf.d/10-faster-shutdown.conf)"
else if demoCfg.systemd.settings.Manager.DefaultLimitNOFILE != "65536:524288" then
  throw "demo config missing DefaultLimitNOFILE (etc/systemd/system.conf.d/20-omarchy-nofile.conf)"
else if !(hasInfix "DefaultLimitNOFILE=65536:524288" userConf) then
  throw "demo config user.conf missing DefaultLimitNOFILE (etc/systemd/user.conf.d/20-omarchy-nofile.conf)"
else if demoCfg.systemd.services.docker.unitConfig.DefaultDependencies != false then
  throw "demo config missing docker DefaultDependencies=no (etc/systemd/system/docker.service.d/no-block-boot.conf)"
else if demoCfg.systemd.services.update-locatedb.unitConfig.ConditionACPower != true then
  throw "demo config missing update-locatedb ConditionACPower=true (etc/systemd/system/plocate-updatedb.service.d/ac-only.conf)"
else if demoCfg.systemd.services."user@".serviceConfig.TimeoutStopSec != "5s" then
  throw "demo config missing user@ TimeoutStopSec=5s (etc/systemd/system/user@.service.d/10-faster-shutdown.conf)"
else if
  !builtins.elem
    (demoCfg.systemd.user.services.omarchy-migrate.serviceConfig.TimeoutStartSec or "infinity")
    [
      "2min"
    ]
then
  # A oneshot has no start timeout by default and omarchy-migrate holds
  # graphical-session.target; it must stay bounded.
  throw "omarchy-migrate lost its bounded TimeoutStartSec (it holds graphical-session.target)"
else if demoCfg.virtualisation.docker.daemon.settings.log-driver != "json-file" then
  throw "demo config missing docker log rotation (etc/docker/daemon.json)"
else if hasSudoCmd "/run/current-system/sw/bin/tzupdate" then
  throw "demo config grants NOPASSWD tzupdate (its -l/-d/-z flags write arbitrary paths as root; upstream only grants timedatectl set-timezone)"
else if builtins.elem "@wheel" demoCfg.nix.settings.trusted-users then
  throw "demo config makes @wheel a trusted Nix user (root-equivalent; the Hyprland cache works from system-level substituters)"
else if
  !(hasSudoCmd "/run/current-system/sw/bin/timedatectl ^set-timezone [A-Za-z0-9_+][A-Za-z0-9_+.-]*(/[A-Za-z0-9_+][A-Za-z0-9_+.-]*)*$")
then
  throw "demo config missing NOPASSWD timedatectl set-timezone regex (etc/sudoers.d/omarchy-tzupdate)"
else if hasSudoCmd "/run/current-system/sw/bin/asdcontrol" then
  throw "demo config still grants NOPASSWD asdcontrol (upstream removed etc/sudoers.d/omarchy-asdcontrol in v4.0.1)"
else if !(hasInfix "passwd_tries=10" demoCfg.security.sudo.extraConfig) then
  throw "demo config missing passwd_tries=10 (etc/sudoers.d/omarchy-passwd-tries)"
else if demoCfg.services.printing.browsed.enable then
  throw "demo config still enables cups-browsed (upstream removed automatic printer discovery in v4.0.2)"
else if !demoCfg.services.printing.enable then
  throw "demo config missing services.printing.enable (CUPS itself stays on)"
else if !(hasInfix "autosuspend=-1" demoCfg.boot.extraModprobeConfig) then
  throw "demo config missing usbcore autosuspend=-1 (etc/modprobe.d/omarchy-usb-autosuspend.conf)"
else if (demoCfg.environment.etc."gnupg/dirmngr.conf".source or null) == null then
  throw "demo config missing /etc/gnupg/dirmngr.conf (etc/gnupg/dirmngr.conf)"
else if
  # The user-manager NOFILE limit is set through a
  # version-dependent API (systemd.user.extraConfig on 26.05,
  # systemd.user.settings.Manager after the option was
  # replaced). Guard the newer branch against the nixpkgs the
  # hyprland input carries (which already has the new API), so a
  # conditional flip cannot silently drop the limit for
  # consumers on unstable.
  #
  # Cost/fragility: this instantiates a second nixpkgs (the
  # hyprland input's) and evaluates a full nixosSystem per
  # `nix flake check` just to probe one option path. It is
  # intentionally narrow; if the hyprland nixpkgs pin drifts or
  # the option moves again, this branch is the first thing to
  # re-check — do not broaden it into a general dual-nixpkgs suite.
  ((inputs.hyprland.inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.default
      {
        omarchy.enable = true;
        system.stateVersion = "26.05";
      }
    ];
  }).config.systemd.user.settings.Manager.DefaultLimitNOFILE or null
  ) != "65536:524288"
then
  throw "newer nixpkgs (systemd.user.settings.Manager API) lost the user-manager DefaultLimitNOFILE"
else
  pkgs.runCommand "omarchy-etc-parity" { } ''
    # Fail-closed inventory, both directions: every file in the
    # vendored etc/ tree must be classified in the manifest and
    # every manifest key must still exist upstream.
    cd ${omarchyPkg}/share/omarchy/etc
    find . -type f | sed 's|^\./||' | LC_ALL=C sort > $TMPDIR/upstream-files
    diff -u ${
      pkgs.writeText "etc-manifest-keys" (builtins.concatStringsSep "\n" manifestKeys + "\n")
    } $TMPDIR/upstream-files || {
      echo "etc/ inventory mismatch — classify new files in pkgs/omarchy-etc-manifest.nix"
      exit 1
    }

    # Generated-file greps (the eval assertions above pin the
    # options; these pin what actually lands in /etc).
    if ! grep -q '^HandlePowerKey=ignore$' ${demoCfg.environment.etc."systemd/logind.conf".source}; then
      echo "logind.conf is missing the exact HandlePowerKey=ignore line"
      exit 1
    fi
    if ! grep -q '^DefaultLimitNOFILE=65536:524288$' ${
      demoCfg.environment.etc."systemd/user.conf".source
    }; then
      echo "user.conf is missing DefaultLimitNOFILE=65536:524288"
      exit 1
    fi
    if ! grep -q '^options usbcore autosuspend=-1$' ${
      demoCfg.environment.etc."modprobe.d/nixos.conf".source
    }; then
      echo "modprobe.d/nixos.conf is missing usbcore autosuspend=-1"
      exit 1
    fi

    # The vendored sources the module/seeds point at must exist
    # in the package (a path typo would only fail at runtime).
    for f in etc/fastfetch/config.jsonc etc/gnupg/dirmngr.conf; do
      if [ ! -f "${omarchyPkg}/share/omarchy/$f" ]; then
        echo "package is missing share/omarchy/$f"
        exit 1
      fi
    done

    touch $out
  ''
