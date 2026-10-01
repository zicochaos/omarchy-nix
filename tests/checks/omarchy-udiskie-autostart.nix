# udiskie runs exactly once: upstream's default/hypr/autostart.lua
# launches `udiskie --automount ...` at session start, so the module
# must not add its own user service (a second instance doubled mounts
# and notifications) and must keep the package on PATH for that line.
# If upstream ever drops the autostart line, this fails so the module
# can take over again.
{
  self,
  system,
  pkgs,
  ...
}:
let
  demoCfg = self.nixosConfigurations.demo.config;
  autostart = "${self.packages.${system}.omarchy}/share/omarchy/default/hypr/autostart.lua";
in
if demoCfg.systemd.user.services ? udiskie then
  throw "demo config defines a udiskie user unit on top of upstream's autostart launch"
else if !(builtins.any (p: pkgs.lib.getName p == "udiskie") demoCfg.environment.systemPackages) then
  throw "udiskie is not on the system PATH (upstream autostart launches it)"
else
  pkgs.runCommand "omarchy-udiskie-autostart" { } ''
    grep -q 'udiskie --automount' ${autostart} || {
      echo "upstream autostart.lua no longer launches udiskie; restore a module unit"
      exit 1
    }
    touch $out
  ''
