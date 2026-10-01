# Module defaults that reach the system, and their documented
# opt-outs (docs/options.md, README):
#   - omarchy.hyprlandCache.enable: the Hyprland Cachix substituter and
#     key are registered by default and gone when disabled, without
#     dropping nixpkgs' own cache.
#   - sshd: on, keys-only (PasswordAuthentication and
#     KbdInteractiveAuthentication off, also in the rendered
#     sshd_config); each is a module default a consumer's plain value
#     replaces.
#   - nix.nixPath pins <nixpkgs> to the system's own nixpkgs (the first
#     nixpkgs= entry); a consumer's nixPath replaces the whole list.
#   - Plymouth: omarchy.plymouth.enable wires the omarchy theme and the
#     injected theme package; false leaves boot.plymouth alone.
#   - the SDDM theme (package, /share/sddm link, theme name) is wired
#     only while SDDM is the display manager.
#   - omarchy.theme: the NixOS module renders nothing from it; it
#     reaches the system through the shared Home-Manager module's
#     first-activation theme render (omarchyThemeRender), so a
#     non-default value must appear there.
# The sshd/nixPath/Plymouth cases use a minimal enabled system (the
# demo config sets services.openssh.enable itself, so a consumer
# `false` on top of it would test the demo, not the module).
{
  self,
  nixpkgs,
  pkgs,
  ...
}:
let
  lib = nixpkgs.lib;
  demo = self.nixosConfigurations.demo;
  ext = m: (demo.extendModules { modules = [ m ]; }).config;
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
  minimal = mkConfig { };
  expect =
    name: got: want:
    if builtins.deepSeq got got == want then
      true
    else
      throw "omarchy-module-defaults: ${name}: got ${builtins.toJSON got}, want ${builtins.toJSON want}";

  cacheUrl = "https://hyprland.cachix.org";
  cacheKey = "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=";
  cache = c: {
    substituter = builtins.elem cacheUrl c.nix.settings.substituters;
    trustedSubstituter = builtins.elem cacheUrl (c.nix.settings.trusted-substituters or [ ]);
    key = builtins.elem cacheKey c.nix.settings.trusted-public-keys;
    nixosCache = builtins.elem "https://cache.nixos.org/" c.nix.settings.substituters;
  };

  sshd = c: {
    enable = c.services.openssh.enable;
    password = c.services.openssh.settings.PasswordAuthentication;
    kbdInteractive = c.services.openssh.settings.KbdInteractiveAuthentication;
  };

  plymouth = c: {
    enable = c.boot.plymouth.enable;
    theme = c.boot.plymouth.theme;
    themePackage = builtins.elem c.omarchy.plymouthPackage.outPath (
      map (p: p.outPath) c.boot.plymouth.themePackages
    );
  };

  sddmTheme = c: {
    package = builtins.any (p: (p.pname or "") == "sddm-omarchy-theme") c.environment.systemPackages;
    linked = builtins.elem "/share/sddm" c.environment.pathsToLink;
    theme = c.services.displayManager.sddm.theme;
  };

  # nixpkgs' flake module adds "nixpkgs=flake:nixpkgs" (+ channels) at
  # the same mkDefault priority, so the lists concatenate; NIX_PATH
  # lookups take the first match, so the pin must come first.
  firstNixpkgs = c: lib.findFirst (e: lib.hasPrefix "nixpkgs=" e) null c.nix.nixPath;

  themeRender = c: c.home-manager.users.demo.home.activation.omarchyThemeRender.data;
  rendersTheme =
    name: c: builtins.match ".*omarchy-theme-set\" \"${name}\".*" (themeRender c) != null;
in
assert expect "hyprlandCache default" (cache demo.config) {
  substituter = true;
  trustedSubstituter = true;
  key = true;
  nixosCache = true;
};
assert expect "hyprlandCache.enable = false"
  (cache (ext {
    omarchy.hyprlandCache.enable = false;
  }))
  {
    substituter = false;
    trustedSubstituter = false;
    key = false;
    nixosCache = true;
  };
assert expect "sshd default" (sshd minimal) {
  enable = true;
  password = false;
  kbdInteractive = false;
};
assert expect "sshd consumer overrides"
  (sshd (mkConfig {
    services.openssh.enable = false;
    services.openssh.settings.PasswordAuthentication = true;
    services.openssh.settings.KbdInteractiveAuthentication = true;
  }))
  {
    enable = false;
    password = true;
    kbdInteractive = true;
  };
assert expect "nixPath default (first nixpkgs= entry wins <nixpkgs>)" (firstNixpkgs minimal)
  "nixpkgs=${toString pkgs.path}";
assert expect "nixPath consumer override"
  (mkConfig { nix.nixPath = [ "nixpkgs=/srv/nixpkgs" ]; }).nix.nixPath
  [ "nixpkgs=/srv/nixpkgs" ];
assert expect "plymouth default" (plymouth minimal) {
  enable = true;
  theme = "omarchy";
  themePackage = true;
};
assert expect "plymouth disabled" (
  (mkConfig { omarchy.plymouth.enable = false; }).boot.plymouth.theme != "omarchy"
) true;
assert expect "sddm theme with SDDM" (sddmTheme demo.config) {
  package = true;
  linked = true;
  theme = "omarchy";
};
assert expect "sddm theme with another display manager"
  (sddmTheme (ext {
    services.displayManager.sddm.enable = false;
    services.displayManager.gdm.enable = true;
  }))
  {
    package = false;
    linked = false;
    theme = "";
  };
assert expect "theme default reaches the HM render" (rendersTheme "ethereal" demo.config) true;
assert expect "theme override reaches the HM render" (rendersTheme "nord" (ext {
  omarchy.theme = "nord";
})) true;
# The rendered sshd_config is grepped at build time (no import from
# derivation during evaluation).
pkgs.runCommand "omarchy-module-defaults" { } ''
  set -euo pipefail
  for line in 'PasswordAuthentication no' 'KbdInteractiveAuthentication no'; do
    grep -qx "$line" ${minimal.environment.etc."ssh/sshd_config".source} ||
      { echo "sshd_config lacks: $line"; exit 1; }
  done
  touch $out
''
