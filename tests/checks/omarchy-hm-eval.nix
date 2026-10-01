# Home-Manager module evaluation (nothing is built): where the omarchy.*
# values come from, and what the module leaves alone.
# - Under NixOS the system configuration drives the seed. A differing value
#   set in Home Manager is ignored with a warning, an equal one is not
#   warned about, and options only the NixOS module reads warn when set in
#   Home Manager.
# - Without osConfig.omarchy (standalone Home Manager, or a system without
#   the omarchy NixOS module), homeModules.default injects the package and
#   the HM-level values are used; the bare module without a package fails
#   an assertion instead of silently seeding nothing.
# - Paths Home Manager programs own are not seeded.
# - The default-browser step stays out of an HM-managed mimeapps.list.
# - The skill-dir relocation (a write) is ordered after writeBoundary.
# Every case reads the per-user configuration of a NixOS evaluation: unlike
# homeManagerConfiguration, that neither throws on failed assertions nor
# traces warnings into the `nix flake check` output. Real standalone
# activation (and with it the injection) is exercised by
# omarchy-hm-activation and omarchy-browser-default.
{
  self,
  inputs,
  nixpkgs,
  pkgs,
  system,
  ...
}:
let
  inherit (pkgs) lib;
  hmUsers =
    systemModule: users:
    (nixpkgs.lib.nixosSystem {
      inherit pkgs;
      modules = [
        inputs.home-manager.nixosModules.home-manager
        systemModule
        {
          fileSystems."/".device = "/dev/null";
          fileSystems."/".fsType = "ext4";
          boot.loader.grub.device = "nodev";
          system.stateVersion = "26.05";
          users.users = lib.mapAttrs (_: _: { isNormalUser = true; }) users;
          home-manager.useGlobalPkgs = true;
          home-manager.users = lib.mapAttrs (name: module: {
            imports = [ module ];
            home.stateVersion = "26.05";
            omarchy.enable = true;
          }) users;
        }
      ];
    }).config.home-manager.users;

  # A system with omarchy (theme nord) and three Home Manager users.
  withSystem =
    hmUsers
      {
        imports = [ self.nixosModules.default ];
        omarchy.enable = true;
        omarchy.theme = "nord";
        home-manager.sharedModules = [ self.homeModules.default ];
      }
      {
        differs = {
          omarchy.theme = "tokyo-night";
          omarchy.full_name = "Someone";
        };
        same.omarchy.theme = "nord";
        unset = { };
      };

  # No omarchy NixOS module: osConfig has no omarchy, as in standalone HM.
  withoutSystem = hmUsers { } {
    flake = {
      imports = [ self.homeModules.default ];
      omarchy.theme = "nord";
      omarchy.full_name = "Someone";
      programs.git = {
        enable = true;
        settings.user.name = "HM Test";
      };
      programs.starship = {
        enable = true;
        settings.add_newline = false;
      };
      xdg.mimeApps.enable = true;
    };
    bare.imports = [ ../../modules/home-manager/default.nix ];
  };

  omarchyWarnings = cfg: lib.filter (lib.hasPrefix "omarchy.") cfg.warnings;
  warnsAbout = name: cfg: lib.any (lib.hasPrefix "omarchy.${name} ") cfg.warnings;
  failedAssertions = cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.assertions);
  rendersTheme =
    theme: cfg:
    lib.hasInfix ''omarchy-theme-set" "${theme}"'' cfg.home.activation.omarchyThemeRender.data;
  seeds =
    target: cfg: lib.hasInfix ''"$HOME/${target}"'' cfg.home.activation.omarchySeedUserConfig.data;
  inherit (withoutSystem) flake bare;
  skillSafety = flake.home.activation.omarchySkillLinkSafety;

  cases = {
    "NixOS: the system theme is seeded, a differing HM value is ignored" =
      rendersTheme "nord" withSystem.differs;
    "NixOS: a differing HM value warns" = warnsAbout "theme" withSystem.differs;
    "NixOS: an option only the NixOS module reads warns" = warnsAbout "full_name" withSystem.differs;
    "NixOS: an HM value equal to the system's does not warn" = omarchyWarnings withSystem.same == [ ];
    "NixOS: without HM values, no warning and the system theme" =
      omarchyWarnings withSystem.unset == [ ] && rendersTheme "nord" withSystem.unset;
    "NixOS: homeModules.default injects nothing, the system's package is used" =
      withSystem.unset.omarchy.package == null;
    "no osConfig.omarchy: homeModules.default injects package and nvimPackage" =
      flake.omarchy.package == self.packages.${system}.omarchy
      && flake.omarchy.nvimPackage == self.packages.${system}.omarchy-nvim;
    "no osConfig.omarchy: the HM theme is seeded without a warning" =
      rendersTheme "nord" flake && !warnsAbout "theme" flake;
    "no osConfig.omarchy: an option only the NixOS module reads warns" = warnsAbout "full_name" flake;
    "no osConfig.omarchy: homeModules.default passes the package assertion" =
      !lib.any (lib.hasInfix "no omarchy package") (failedAssertions flake);
    "no osConfig.omarchy: the bare module without a package fails an assertion" =
      lib.any (lib.hasInfix "no omarchy package") (failedAssertions bare);
    "paths HM programs own are not seeded" =
      !seeds ".config/git/config" flake
      && !seeds ".config/starship.toml" flake
      && seeds ".config/hypr/hyprland.lua" flake;
    "no default-browser step when HM owns mimeapps.list" =
      flake.home.activation.omarchyDefaultBrowser.data == "";
    "the skill-dir relocation runs between writeBoundary and linkGeneration" =
      lib.elem "writeBoundary" skillSafety.after && lib.elem "linkGeneration" skillSafety.before;
  };
  failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
in
if failed != [ ] then
  throw "omarchy-hm-eval: ${lib.concatStringsSep "; " failed}"
else
  pkgs.runCommand "omarchy-hm-eval-check" { } "touch $out"
