# Omarchy Plymouth boot-splash theme.
#
# Packages upstream's default/plymouth/ tree (the Omarchy splash: script +
# PNG assets + the logos/ subdir) as a NixOS plymouth theme at
# $out/share/plymouth/themes/omarchy/, with the hardcoded /usr paths in
# omarchy.plymouth rewritten into the nix store. The script itself uses
# bare Image("logo.png") lookups resolved against ImageDir, so it needs no
# patching.
#
# Pattern follows nixpkgs plymouth theme packages (catppuccin-plymouth,
# plymouth-proxzima-theme): stdenvNoCC, data-only install, single
# substituteInPlace on the .plymouth config.
{
  stdenvNoCC,
  lib,
  omarchy-src,
  version,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "plymouth-omarchy-theme";
  inherit version;

  src = omarchy-src;
  sourceRoot = "source/default/plymouth";

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/plymouth/themes/omarchy"
    mkdir -p "$dest"

    # Copy the whole theme dir verbatim: the .plymouth config, the script
    # that drives the splash animation, the PNG assets, and the logos/
    # subdir (omarchy script loads vendor logos from there).
    cp -r . "$dest/"

    # Rewrite the hardcoded /usr/share paths in the config to this output.
    # Both ImageDir and ScriptFile point at /usr/share/plymouth/themes/omarchy;
    # --replace-fail "/usr/" "$out/" catches both in one pass (proxzima pattern).
    substituteInPlace "$dest/omarchy.plymouth" \
      --replace-fail "/usr/" "$out/"

    runHook postInstall
  '';

  meta = {
    description = "Omarchy (Quattro) Plymouth boot splash theme";
    homepage = "https://github.com/basecamp/omarchy";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
})
