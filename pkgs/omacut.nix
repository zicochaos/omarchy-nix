# omacut — upstream-owned Omarchy app: a dead-simple video length trimmer.
# Qt6 Quick/QML app built with qmake6 (see omacut.pro); compiles to a single
# `omacut` executable with the QML embedded via Qt resources. ffmpeg/ffprobe
# are invoked at runtime (on PATH), so they are a runtime dep, not a build dep.
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omacut";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "omacom-io";
    repo = "omacut";
    rev = "v${finalAttrs.version}";
    hash = "sha256-B1MkokDbvqV4et0Ox31mmtV/JjhnHEOQhLIuxhFEkkY=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative # includes Qt Quick Controls 2 (merged in Qt 6.2)
    qt6.qtmultimedia
  ];

  enableParallelBuilding = true;

  # omacut.pro defines no install targets, so install by hand (matches
  # pkgbuild/PKGBUILD: binary + desktop file + scalable icon).
  installPhase = ''
    runHook preInstall
    install -Dm555 omacut "$out/bin/omacut"
    install -Dm644 pkgbuild/omacut.svg \
      "$out/share/icons/hicolor/scalable/apps/omacut.svg"
    install -Dm644 pkgbuild/omacut.desktop \
      "$out/share/applications/omacut.desktop"
    runHook postInstall
  '';

  meta = {
    description = "Dead-simple video length trimmer (Omarchy app)";
    homepage = "https://github.com/omacom-io/omacut";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omacut";
  };
})
