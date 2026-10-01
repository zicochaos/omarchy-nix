# Taildrop follows the effective Tailscale service setting, including
# menu-managed installation and an explicit consumer opt-out.
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  mkConfig =
    extra:
    (nixpkgs.lib.nixosSystem {
      inherit pkgs;
      modules = [
        self.nixosModules.default
        {
          omarchy.enable = true;
          system.stateVersion = "26.05";
        }
        extra
      ];
    }).config;
  managed = {
    # Real fixture file (see the note in omarchy-managed-nested-attrs):
    # toFile + pathExists breaks --no-build evaluation after a GC.
    omarchy.managedPackagesFile = ../fixtures/managed-packages-taildrop.json;
  };
  enabled = mkConfig managed;
  disabled = mkConfig { };
  overridden = mkConfig (managed // { services.tailscale.enable = false; });
  noPackage = mkConfig {
    services.tailscale.enable = true;
    omarchy.package = null;
  };
  startsReceiver =
    cfg:
    builtins.elem "graphical-session.target" (
      cfg.systemd.user.services.omarchy-tailscale-receive.wantedBy or [ ]
    );
in
assert enabled.services.tailscale.enable;
assert startsReceiver enabled;
assert !(startsReceiver disabled);
assert !(startsReceiver overridden);
assert !(startsReceiver noPackage);
pkgs.runCommand "omarchy-taildrop-check" { } "touch $out"
