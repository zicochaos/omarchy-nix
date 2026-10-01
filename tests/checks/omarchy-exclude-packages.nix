# omarchy.exclude_packages contract (docs/options.md): entries are
# nixpkgs attribute names, matched against the module's own lists.
#   - attribute names whose pname differs (libreoffice-fresh ->
#     libreoffice, tesseract5 -> tesseract) or is shared (qt5/qt6
#     qtwayland) remove exactly that package;
#   - plain package names keep working (obsidian, the flake-injected
#     owe app, whose owed unit follows it);
#   - excluding chromium also drops the chromium.desktop alias built
#     from it;
#   - an entry matching nothing warns instead of silently doing
#     nothing, and the stock demo config carries no warning.
{
  self,
  pkgs,
  ...
}:
let
  demo = self.nixosConfigurations.demo;
  dpkgs = demo.pkgs;
  cfg =
    (demo.extendModules {
      modules = [
        {
          omarchy.exclude_packages = [
            "libreoffice-fresh"
            "tesseract5"
            "qt5.qtwayland"
            "obsidian"
            "owe"
            "chromium"
            "no-such-package"
          ];
        }
      ];
    }).config;
  outs = map (p: p.outPath) cfg.environment.systemPackages;
  names = map (p: p.name or "") cfg.environment.systemPackages;
  has = p: builtins.elem p.outPath outs;
  hasName = re: builtins.any (n: builtins.match re n != null) names;
  unmatched = builtins.filter (
    w: builtins.match ".*omarchy.exclude_packages.*" w != null
  ) cfg.warnings;
in
if has dpkgs.libreoffice-fresh then
  throw "exclude_packages: \"libreoffice-fresh\" (pname libreoffice) did not remove it"
else if has dpkgs.tesseract5 then
  throw "exclude_packages: \"tesseract5\" (pname tesseract) did not remove it"
else if has dpkgs.qt5.qtwayland then
  throw "exclude_packages: \"qt5.qtwayland\" did not remove it"
else if !(has dpkgs.qt6.qtwayland) then
  throw "exclude_packages: \"qt5.qtwayland\" also removed qt6.qtwayland (shared pname)"
else if has dpkgs.obsidian then
  throw "exclude_packages: pname match (\"obsidian\") no longer works"
else if hasName "owe-.*" || cfg.systemd.user.services ? owed then
  throw "exclude_packages: \"owe\" left the app package or its owed unit"
else if has dpkgs.chromium || hasName "chromium-desktop-alias" then
  throw "exclude_packages: \"chromium\" left chromium or its desktop alias"
else if
  builtins.length unmatched != 1
  || builtins.match ".*\"no-such-package\".*" (builtins.head unmatched) == null
then
  throw "exclude_packages: expected exactly one warning, for \"no-such-package\"; got ${builtins.toJSON unmatched}"
else if demo.config.warnings != [ ] then
  throw "demo config has warnings: ${builtins.toJSON demo.config.warnings}"
else
  pkgs.runCommand "omarchy-exclude-packages" { } "touch $out"
