# Module defaults a consumer must be able to override with a plain
# definition: every value here is a module default (mkDefault), so a
# consumer's own `false` / own command replaces it instead of raising
# "conflicting definition values" or being silently overridden. Also
# the greeter's default session: the uwsm entry without autologin, a
# desktop module's own mkDefault (plasma6) winning without a conflict,
# and a consumer's explicit choice.
{
  self,
  pkgs,
  ...
}:
let
  demo = self.nixosConfigurations.demo;
  ext = m: (demo.extendModules { modules = [ m ]; }).config;
  # Force a value; a definition conflict throws here (tryEval would
  # hide which case broke, so let it propagate).
  expect =
    name: got: want:
    if builtins.deepSeq got got == want then
      true
    else
      throw "omarchy-consumer-overrides: ${name}: got ${builtins.toJSON got}, want ${builtins.toJSON want}";
  sddmCmd = "weston --shell=kiosk";
  overridden = ext {
    omarchy.autologin.user = "demo";
    services.displayManager.sddm.autoLogin.relogin = false;
    security.rtkit.enable = false;
    services.pipewire.enable = false;
    services.pipewire.alsa.enable = false;
    services.pipewire.alsa.support32Bit = false;
    services.pipewire.pulse.enable = false;
    services.displayManager.sddm.settings.Wayland.CompositorCommand = sddmCmd;
  };
in
assert expect "relogin" overridden.services.displayManager.sddm.autoLogin.relogin false;
assert expect "rtkit" overridden.security.rtkit.enable false;
assert expect "pipewire" overridden.services.pipewire.enable false;
assert expect "pipewire.alsa.support32Bit" overridden.services.pipewire.alsa.support32Bit false;
assert expect "defaultSession (demo, no autologin)"
  demo.config.services.displayManager.defaultSession
  "hyprland-uwsm";
assert expect "defaultSession (plasma6 alongside)"
  (ext { services.desktopManager.plasma6.enable = true; }).services.displayManager.defaultSession
  "plasma";
assert expect "defaultSession (consumer)"
  (ext { services.displayManager.defaultSession = "hyprland"; })
  .services.displayManager.defaultSession
  "hyprland";
# The rendered sddm.conf (what the daemon reads) is grepped at build
# time, not via readFile, so evaluation needs no build.
pkgs.runCommand "omarchy-consumer-overrides" { } ''
  set -euo pipefail
  grep -qxF 'CompositorCommand=${sddmCmd}' ${
    overridden.environment.etc."sddm.conf.d/00-nixos.conf".source
  } || { echo "consumer sddm CompositorCommand did not win"; exit 1; }
  grep -qx 'CompositorCommand=Hyprland --config /nix/store/.*/share/sddm/hyprland.lua' ${
    demo.config.environment.etc."sddm.conf.d/00-nixos.conf".source
  } || { echo "default sddm CompositorCommand is not the Hyprland greeter"; exit 1; }
  grep -qxF 'DefaultSession=hyprland-uwsm.desktop' ${
    demo.config.environment.etc."sddm.conf.d/00-nixos.conf".source
  } || { echo "greeter does not default to the uwsm session without autologin"; exit 1; }
  touch $out
''
