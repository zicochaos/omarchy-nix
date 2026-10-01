# Unfree whitelist on the real consumer path (NixOS owns the nixpkgs
# instance, so block (B0) applies). The consumer defines its OWN
# allowUnfreePredicate, which used to replace the module's mkDefault
# predicate outright: obsidian (default app) and menu-managed unfree
# packages (steam via the ux fixture's `steam` feature) then failed
# evaluation. The module's names now go through the merging
# allowUnfreePackages list, so both the module's packages and the
# consumer's own predicate-allowed package (vscode) must evaluate.
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  lib = nixpkgs.lib;
  sys = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.default
      (
        { pkgs, ... }:
        {
          omarchy.enable = true;
          omarchy.managedPackagesFile = ../fixtures/managed-packages-ux.json;
          nixpkgs.config.allowUnfreePredicate = p: builtins.elem (lib.getName p) [ "vscode" ];
          environment.systemPackages = [ pkgs.vscode ];
          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
          system.stateVersion = "26.05";
        }
      )
    ];
  };
  allowed = sys.config.nixpkgs.config.allowUnfreePackages or [ ];
in
# Forcing the toplevel first evaluates obsidian, steam and vscode
# through check-meta; an unfree refusal (the original symptom) throws
# here.
builtins.seq sys.config.system.build.toplevel.drvPath (
  if
    !(builtins.all (n: builtins.elem n allowed) [
      "obsidian"
      "steam"
      "steam-unwrapped"
    ])
  then
    throw "omarchy-unfree-consumer: allowUnfreePackages lacks the module's names: ${builtins.toJSON allowed}"
  else
    pkgs.runCommand "omarchy-unfree-consumer" { } "touch $out"
)
