# Fish wiring: with omarchy.fish.enable = true the module
# sets programs.fish.enable and puts the vendored profile in the
# system profile; the default (off) adds neither (demo config is the
# off witness). Same eval-time assertion pattern as the disabled-state
# module check.
{
  self,
  nixpkgs,
  pkgs,
  system,
  ...
}:
let
  fishPkg = self.packages.${system}.omarchy-fish;
  mkEval =
    extra:
    nixpkgs.lib.nixosSystem {
      # Same pinned pkgs instance the other module checks use —
      # carries the scoped unfree predicate the omarchy default
      # app set needs at eval (obsidian). `inherit system` instead
      # would re-import nixpkgs without it and fail on unfree.
      inherit pkgs;
      modules = [
        self.nixosModules.default
        {
          omarchy.enable = true;
          omarchy.fish.enable = true;
          fileSystems."/".device = "/dev/null";
          fileSystems."/".fsType = "ext4";
          boot.loader.grub.device = "nodev";
          system.stateVersion = "26.05";
        }
        extra
      ];
    };
  cfg = (mkEval { }).config;
  # Consumer overrides EDITOR only: the SUDO_EDITOR indirection
  # must stay intact so pam_env expands the override at login
  # (upstream's SUDO_EDITOR="$EDITOR" semantics).
  editorCfg = (mkEval { environment.sessionVariables.EDITOR = "nvim"; }).config;
  pamEnv = cfg.environment.etc."pam/environment".source;
  hasFish = builtins.any (p: (p.drvPath or "") == fishPkg.drvPath) cfg.environment.systemPackages;
in
if !cfg.programs.fish.enable then
  throw "omarchy.fish.enable did not set programs.fish.enable"
else if !hasFish then
  throw "omarchy-fish package missing from environment.systemPackages"
else if self.nixosConfigurations.demo.config.programs.fish.enable then
  throw "fish must default to off — demo config has programs.fish.enable"
else if cfg.environment.sessionVariables.SUDO_EDITOR != "\${EDITOR}" then
  throw "SUDO_EDITOR must carry the pam_env \${EDITOR} indirection"
else if editorCfg.environment.sessionVariables.SUDO_EDITOR != "\${EDITOR}" then
  throw "SUDO_EDITOR indirection must survive an EDITOR override"
else if cfg.system.build.toplevel.drvPath == null then
  throw "unreachable" # forces full evaluation incl. assertions
else
  pkgs.runCommand "omarchy-fish-module-check" { } ''
    # pam_env expands ''${EDITOR} at login in file order — the
    # EDITOR line must precede the SUDO_EDITOR line, and the
    # indirection must survive the renderer verbatim.
    ed=$(grep -n '^EDITOR[[:space:]]' ${pamEnv} | cut -d: -f1)
    se=$(grep -n '^SUDO_EDITOR[[:space:]]' ${pamEnv} | cut -d: -f1)
    [ -n "$ed" ] && [ -n "$se" ] || { echo "EDITOR/SUDO_EDITOR missing in pam/environment"; exit 1; }
    [ "$ed" -lt "$se" ] || { echo "EDITOR line must precede SUDO_EDITOR in pam/environment"; exit 1; }
    grep -q '^SUDO_EDITOR[[:space:]]*DEFAULT="''${EDITOR}"$' ${pamEnv} || {
      echo "SUDO_EDITOR lost the ''${EDITOR} indirection in pam/environment"; exit 1; }
    touch $out
  ''
