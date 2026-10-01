# binfmt plumbing: the opt-in list must stay empty on
# the demo config (no silent emulation) and reach
# boot.binfmt.emulatedSystems unchanged when set. extendModules
# derives the positive case from the demo config.
{
  self,
  pkgs,
  ...
}:
let
  demoCfg = self.nixosConfigurations.demo.config;
  withBinfmt =
    (self.nixosConfigurations.demo.extendModules {
      modules = [ { omarchy.binfmtEmulatedSystems = [ "aarch64-linux" ]; } ];
    }).config;
in
if demoCfg.boot.binfmt.emulatedSystems != [ ] then
  throw "demo config must keep boot.binfmt.emulatedSystems empty by default"
else if withBinfmt.boot.binfmt.emulatedSystems != [ "aarch64-linux" ] then
  throw "omarchy.binfmtEmulatedSystems does not reach boot.binfmt.emulatedSystems"
else
  pkgs.runCommand "omarchy-binfmt-eval" { } "touch $out"
