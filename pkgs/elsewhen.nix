# Elsewhen, the world clock shell plugin (upstream ships it as the `elsewhen`
# Arch package since the 2026-09-19 quattro bump; see install/omarchy-base.packages
# and migration 1789581661). Source is the omacom/elsewhen release tree; the
# packaged file set mirrors the upstream PKGBUILD's allow-list
# (omacom/omarchy-pkgs, pkgbuilds/elsewhen): manifest.json, data files and the
# QML/JS entry points. tests/, scripts/ and .github/ never reach the package.
#
# Layout matches the Arch package's plugin root — /usr/share/omarchy/plugins/
# omacom.elsewhen — so the shell-side discovery flows (the ~/.config/omarchy/
# plugins symlink and `omarchy plugin clone`) behave exactly as upstream.
{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation rec {
  pname = "elsewhen";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "elsewhen";
    rev = "v${version}";
    # Same upstream release the PKGBUILD pins (omacom/omarchy-pkgs,
    # pkgbuilds/elsewhen; its archive/refs/tags tarball is
    # 3124f0c0a19ebc1b158bcf04151cddd6c733ceeead88052186b6a54c46bee263 —
    # fetchFromGitHub's codeload serialization of the identical tree differs).
    hash = "sha256-UZ+p/ZkqtjGOxwxFaCXRkBzlJeyWHRP3VrlH04ylak8=";
  };

  # Fail the build on a release tree that cannot load, mirroring the
  # PKGBUILD's manifest/entry-point assertions.
  postPatch = ''
    grep -Eq '"id"[[:space:]]*:[[:space:]]*"omacom\.elsewhen"' manifest.json \
      || { echo "manifest.json does not declare the plugin id omacom.elsewhen" >&2; exit 1; }
    grep -Eq '"barWidget"[[:space:]]*:[[:space:]]*"Panel\.qml"' manifest.json \
      || { echo "manifest.json does not name Panel.qml as the bar widget entry point" >&2; exit 1; }
    [[ -f Panel.qml ]] || { echo "release tree is missing the entry point Panel.qml" >&2; exit 1; }
  '';

  installPhase = ''
    runHook preInstall

    plugin="$out/share/omarchy/plugins/omacom.elsewhen"
    mkdir -p "$plugin"
    # worldclock-data.py runs as `python3 <path>` and needs no execute bit
    # (0644, like the PKGBUILD's install -Dm644).
    for file in manifest.json cities.json world.json worldclock-data.py *.qml *.js; do
      install -Dm644 "$file" "$plugin/$file"
    done

    runHook postInstall
  '';

  meta = {
    description = "World clock plugin for the Omarchy shell";
    homepage = "https://github.com/omacom/elsewhen";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
