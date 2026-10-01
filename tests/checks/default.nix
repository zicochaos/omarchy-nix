# Flake checks: flake.nix sets `checks.<system>` to this attrset. One file
# per check in this directory (file name = attribute name); helpers shared
# by more than one check live in lib.nix. The four NixOS VM tests stay in
# tests/{desktop,ux,fish,sddm}.nix and are applied through loadTest.
{
  self,
  inputs,
  nixpkgs,
  pkgs,
  system,
  ownedPackages,
}:
let
  checkLib = import ./lib.nix { inherit self inputs pkgs; };
  inherit (checkLib) loadTest;
  # Every check file takes the subset of these it uses (plus `...`).
  args = {
    inherit
      self
      inputs
      nixpkgs
      pkgs
      system
      ownedPackages
      ;
    inherit (checkLib) optLoaderGolden;
  };
in
{
  omarchy-desktop = pkgs.testers.nixosTest (loadTest ../desktop.nix);
  # UX/acceptance test: exercises real user behavior (Super+Enter ->
  # foot, session env, default browser, cursor, first-run, systemd user
  # units) on top of the desktop.nix baseline. See tests/ux.nix.
  omarchy-ux = pkgs.testers.nixosTest (loadTest ../ux.nix);
  # Fish profile acceptance: login shell, vendor dirs, session env,
  # completion contract, override precedence. See tests/fish.nix.
  omarchy-fish = pkgs.testers.nixosTest (loadTest ../fish.nix);
  # SDDM -> session acceptance: the real login path (daemon, Wayland
  # greeter wiring, theme, autologin session handoff) the other VM
  # tests bypass by starting from tty1. See tests/sddm.nix.
  omarchy-sddm = pkgs.testers.nixosTest (loadTest ../sddm.nix);
  # Eval-only guard for the manual tests/probe-quickshell-reload.nix (no
  # VM run; not a VM test, so it has no `driver` attribute of its own).
  omarchy-probe-quickshell-reload-eval = import ./omarchy-probe-quickshell-reload-eval.nix args;
  omarchy-skill = import ./omarchy-skill.nix args;
  catalog-consistency = import ./catalog-consistency.nix args;
  omarchy-migrations = import ./omarchy-migrations.nix args;
  omarchy-shebangs = import ./omarchy-shebangs.nix args;
  omarchy-pam-eval = import ./omarchy-pam-eval.nix args;
  omarchy-sleep-lock-path = import ./omarchy-sleep-lock-path.nix args;
  omarchy-quickshell-version = import ./omarchy-quickshell-version.nix args;
  omarchy-icon-font = import ./omarchy-icon-font.nix args;
  omarchy-menu-guards = import ./omarchy-menu-guards.nix args;
  omarchy-binfmt-eval = import ./omarchy-binfmt-eval.nix args;
  omarchy-migration-parity = import ./omarchy-migration-parity.nix args;
  omarchy-etc-parity = import ./omarchy-etc-parity.nix args;
  omarchy-disabled-state = import ./omarchy-disabled-state.nix args;
  omarchy-runtime = import ./omarchy-runtime.nix args;
  omarchy-nix-transactions = import ./omarchy-nix-transactions.nix args;
  omarchy-flake-resolver = import ./omarchy-flake-resolver.nix args;
  omarchy-managed-options = import ./omarchy-managed-options.nix args;
  omarchy-option-validation = import ./omarchy-option-validation.nix args;
  omarchy-options-documented = import ./omarchy-options-documented.nix args;
  omarchy-fish-package = import ./omarchy-fish-package.nix args;
  omarchy-fish-parity = import ./omarchy-fish-parity.nix args;
  omarchy-fish-module = import ./omarchy-fish-module.nix args;
  omarchy-managed-nested-attrs = import ./omarchy-managed-nested-attrs.nix args;
  omarchy-browser-default = import ./omarchy-browser-default.nix args;
  omarchy-taildrop = import ./omarchy-taildrop.nix args;
  omarchy-launch-desktop-glob = import ./omarchy-launch-desktop-glob.nix args;
  omarchy-owned-packages = import ./omarchy-owned-packages.nix args;
  omarchy-hm-activation = import ./omarchy-hm-activation.nix args;
  omarchy-hm-eval = import ./omarchy-hm-eval.nix args;
  omarchy-update-flow = import ./omarchy-update-flow.nix args;
  omarchy-migration-adapters = import ./omarchy-migration-adapters.nix args;
  omarchy-build-guards = import ./omarchy-build-guards.nix args;
  omarchy-bash-syntax = import ./omarchy-bash-syntax.nix args;
  omarchy-qml-commands = import ./omarchy-qml-commands.nix args;
  omarchy-exclude-packages = import ./omarchy-exclude-packages.nix args;
  omarchy-unfree-consumer = import ./omarchy-unfree-consumer.nix args;
  omarchy-udiskie-autostart = import ./omarchy-udiskie-autostart.nix args;
  omarchy-system-tuning = import ./omarchy-system-tuning.nix args;
  omarchy-consumer-overrides = import ./omarchy-consumer-overrides.nix args;
  omarchy-module-defaults = import ./omarchy-module-defaults.nix args;
}
