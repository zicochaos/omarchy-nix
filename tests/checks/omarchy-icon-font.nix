# Menu icon font: the vendored font ships one glyph per app
# (U+E900..U+E90E) and this repo injects the ZCode mark U+E90F
# (pkgs/omarchy-icons/). Assert the injection and the family name,
# so a silently unapplied postPatch, or an upstream font swap that
# renumbers the codepoints, cannot ship a menu with missing icons.
{
  self,
  pkgs,
  system,
  ...
}:
let
  fontToolsPython = pkgs.python3.withPackages (ps: [ ps.fonttools ]);
in
pkgs.runCommand "omarchy-icon-font" { } ''
  ${fontToolsPython}/bin/python3 -c '
  from fontTools.ttLib import TTFont
  font = TTFont("${self.packages.${system}.omarchy}/share/fonts/omarchy/omarchy.ttf")
  cmap = font.getBestCmap()
  assert cmap.get(0xE90F) == "zcode", "ZCode mark (U+E90F) missing from the menu icon font"
  family = font["name"].getDebugName(1)
  assert family == "omarchy", f"icon font family changed: {family}"
  print(f"menu icon font: {len(cmap)} codepoints, U+E90F -> zcode, family {family}")
  '
  touch $out
''
