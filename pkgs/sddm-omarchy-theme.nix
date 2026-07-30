# Omarchy SDDM greeter theme + Hyprland greeter config.
#
# Packages upstream's default/sddm/ as two outputs:
#   - $out/share/sddm/themes/omarchy/  : the QML login theme (Main.qml + PNG
#     assets + metadata.desktop + theme.conf) that SDDM discovers via the
#     standard themes/ XDG data path.
#   - $out/share/sddm/hyprland.lua     : the minimal Hyprland config for the
#     SDDM Wayland greeter (SDDM starts Hyprland with --config pointing here
#     so the greeter composites under Hyprland instead of weston/kwin).
#
# The omarchy NixOS module wires services.displayManager.sddm.theme to
# "omarchy" and adds this package to themePackages so SDDM finds it on the
# system profile; the greeter config is consumed via the module's
# Wayland.CompositorCommand override.
#
# stdenvNoCC: data-only (QML + PNGs + Lua), no compilation.
{
  stdenvNoCC,
  lib,
  omarchy-src,
  version,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "sddm-omarchy-theme";
  inherit version;

  src = omarchy-src;
  sourceRoot = "source/default/sddm";

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Theme: the QML greeter + assets. SDDM looks up themes under
    # $XDG_DATA_DIRS/sddm/themes/<name>/, so the dir name must be "omarchy"
    # (matching services.displayManager.sddm.theme = "omarchy").
    mkdir -p "$out/share/sddm/themes/omarchy"
    cp -r omarchy/. "$out/share/sddm/themes/omarchy/"

    # Greeter Hyprland config: SDDM's CompositorCommand launches Hyprland
    # with --config pointing at this file (see the NixOS module).
    cp hyprland.lua "$out/share/sddm/hyprland.lua"

    runHook postInstall
  '';

  meta = {
    description = "Omarchy (Quattro) SDDM login theme + Hyprland greeter config";
    homepage = "https://github.com/basecamp/omarchy";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
