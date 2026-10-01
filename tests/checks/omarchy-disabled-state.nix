# Disabled-state contract: merely IMPORTING
# nixosModules.default with omarchy.enable = false must not change
# the host. The assertion is the whole system: a baseline without the
# module and one importing it disabled must have the same toplevel
# drvPath, so any leak (a sysctl, a unit, an /etc file, a package, a
# nixpkgs.config entry) fails. A sampled subset of observables (Mesa,
# packages, sessions, /etc, caches, hyprland) is only computed for the
# failure message, to point at the leak. The Mesa assertions guard the
# other half of the contract: with omarchy enabled, the demo config
# selects the Hyprland-input Mesa for both halves (consumer override
# is a plain `=`, which wins over mkOverride 500 by definition).
{
  self,
  inputs,
  nixpkgs,
  pkgs,
  system,
  ...
}:
let
  lib = nixpkgs.lib;
  base = {
    system.stateVersion = "26.05";
    # A real consumer has graphics enabled (via their desktop or
    # explicitly); that is what gives hardware.graphics.package
    # its stable-nixpkgs Mesa default to be clobbered.
    hardware.graphics.enable = true;
    # The minimum for system.build.toplevel to pass NixOS's own
    # assertions (root file system, a boot loader decision).
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    boot.loader.grub.enable = false;
  };
  baseline = nixpkgs.lib.nixosSystem {
    inherit pkgs;
    modules = [ base ];
  };
  disabled = nixpkgs.lib.nixosSystem {
    inherit pkgs;
    modules = [
      base
      self.nixosModules.default
      { omarchy.enable = false; }
    ];
  };
  # Diagnostics only (see header).
  observables = c: {
    mesa = c.hardware.graphics.package.drvPath;
    mesa32 = c.hardware.graphics.package32.drvPath;
    systemPackages = builtins.sort (a: b: a < b) (
      map (p: p.name or "unknown") c.environment.systemPackages
    );
    sessionPackages = map (p: p.name or "unknown") c.services.displayManager.sessionPackages;
    sddm = c.services.displayManager.sddm.enable;
    hyprland = c.programs.hyprland.enable;
    etcNames = builtins.attrNames c.environment.etc;
    substituters = c.nix.settings.substituters or [ ];
  };
  differing =
    let
      b = observables baseline.config;
      d = observables disabled.config;
    in
    builtins.filter (n: b.${n} != d.${n}) (builtins.attrNames b);
  hyprlandPkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${system};
  demoGraphics = self.nixosConfigurations.demo.config.hardware.graphics;
in
if
  baseline.config.system.build.toplevel.drvPath != disabled.config.system.build.toplevel.drvPath
then
  throw (
    "nixosModules.default has import-time side effects with omarchy.enable = false "
    + "(system.build.toplevel drvPath differs from the baseline). Sampled observables that differ: "
    + (
      if differing == [ ] then
        "none; compare the two toplevels with nix-diff"
      else
        lib.concatStringsSep ", " differing
    )
  )
else if demoGraphics.package.drvPath != hyprlandPkgs.mesa.drvPath then
  throw "enabled omarchy no longer selects the Hyprland-input Mesa"
else if demoGraphics.package32.drvPath != hyprlandPkgs.pkgsi686Linux.mesa.drvPath then
  throw "enabled omarchy selects a 32-bit Mesa from a different nixpkgs than the 64-bit one"
else
  pkgs.runCommand "omarchy-disabled-state" { } "touch $out"
