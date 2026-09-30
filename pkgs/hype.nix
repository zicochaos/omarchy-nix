# hype — upstream-owned Omarchy app: dead-simple Markdown presentations with a
# visual slide editor (default app since 8b4eae6). Qt6 Quick/QML app built
# with qmake (see hype.pro); compiles to a single `hype` executable with the
# QML embedded via Qt resources. The PPTX exporter links zlib and the
# animation exporter libwebp (LIBS in hype.pro).
#
# Runtime tools (pkgbuild/PKGBUILD depends): ffmpeg/ffprobe for video posters
# and exports come from the session PATH (the NixOS module ships ffmpeg, as
# for omacut and monologue). source-highlight is hype-only, so it is put on
# the wrapper's PATH here. The save picker talks to xdg-desktop-portal over
# dbus. qt6-imageformats and qt6-svg are image plugins, wired through
# wrapQtAppsHook via buildInputs.
#
# Qt modules from hype.pro:
#   core gui dbus concurrent -> qtbase
#   qml quick quickcontrols2  -> qtdeclarative (merged in Qt6)
#   multimedia               -> qtmultimedia
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  zlib,
  libwebp,
  sourceHighlight,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hype";
  version = "0.4.3";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "hype";
    rev = "v${finalAttrs.version}";
    hash = "sha256-GOhNOPuOf4eXcXUZfylJYccUW7vsifAahqOIBzytZ48=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  # core/gui/dbus/concurrent -> qtbase
  # qml/quick/quickcontrols2 -> qtdeclarative (merged in Qt6)
  # multimedia -> qtmultimedia; imageformats/svg -> runtime image plugins
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtimageformats
    qt6.qtsvg
    zlib
    libwebp
  ];

  enableParallelBuilding = true;

  qtWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ sourceHighlight ]}"
  ];

  # hype.pro defines no install targets (upstream's bin/build only runs
  # qmake + make), so install by hand (matches pkgbuild/PKGBUILD: binary +
  # license + desktop file + scalable icon).
  installPhase = ''
    runHook preInstall
    install -Dm555 hype "$out/bin/hype"
    install -Dm644 LICENSE "$out/share/licenses/hype/LICENSE"
    install -Dm644 pkgbuild/hype.svg \
      "$out/share/icons/hicolor/scalable/apps/hype.svg"
    install -Dm644 pkgbuild/hype.desktop \
      "$out/share/applications/hype.desktop"
    runHook postInstall
  '';

  meta = {
    description = "Simple Markdown presentations with a visual slide editor (Omarchy app)";
    homepage = "https://github.com/omacom/hype";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hype";
  };
})
