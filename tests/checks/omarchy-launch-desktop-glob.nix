# omarchy-launch-browser and omarchy-launch-webapp resolve the
# default/chromium .desktop via a fixed brace list of data dirs.
# Arch has /usr/share/applications; NixOS puts system apps in
# /run/current-system/sw/share/applications. Both launchers must
# search that path — webapps used to drop the Exec= lookup, so
# uwsm-app treated --app=https://… as the application path.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  nixosGlob = "{~/.local,~/.nix-profile,/run/current-system/sw,/usr}/share/applications";
  archGlob = "{~/.local,~/.nix-profile,/usr}/share/applications";
in
pkgs.runCommand "omarchy-launch-desktop-glob" { } ''
  webapp=${omarchyPkg}/share/omarchy/bin/omarchy-launch-webapp
  browser=${omarchyPkg}/share/omarchy/bin/omarchy-launch-browser
  grep -Fq '${nixosGlob}' "$webapp" || {
    echo "omarchy-launch-webapp missing NixOS applications glob" >&2
    exit 1
  }
  grep -Fq '${nixosGlob}' "$browser" || {
    echo "omarchy-launch-browser missing NixOS applications glob" >&2
    exit 1
  }
  grep -Fq '${archGlob}' "$webapp" && {
    echo "omarchy-launch-webapp still has the Arch-only applications glob" >&2
    exit 1
  }
  grep -Fq '${archGlob}' "$browser" && {
    echo "omarchy-launch-browser still has the Arch-only applications glob" >&2
    exit 1
  }
  touch $out
''
