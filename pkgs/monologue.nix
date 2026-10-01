# monologue — upstream-owned Omarchy app: a dead-simple, theme-synced webcam
# recorder. Qt6 Quick/QML app built with qmake (see monologue.pro); compiles to
# a single `monologue` executable with the QML embedded via Qt resources.
# Audio capture links libpulse via pkg-config (src/common.pri). ffmpeg/ffprobe
# are invoked at runtime (on PATH) for probing/remuxing, and the save picker
# talks to xdg-desktop-portal over dbus, so both are runtime deps of the
# environment, not build deps here.
#
# Qt modules from monologue.pro:
#   core gui dbus concurrent -> qtbase
#   qml quick quickcontrols2  -> qtdeclarative (merged in Qt6)
#   multimedia               -> qtmultimedia
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  qt6,
  libpulseaudio,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "monologue";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "monologue";
    rev = "v${finalAttrs.version}";
    hash = "sha256-juzlFfzZ9ZtCKwy8/ckJAOhgN+4NwZ3QyN4Fzr8Vvqs=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config # common.pri: CONFIG += link_pkgconfig, PKGCONFIG += libpulse
  ];

  # core/gui/dbus/concurrent -> qtbase
  # qml/quick/quickcontrols2 -> qtdeclarative (merged in Qt6)
  # multimedia -> qtmultimedia
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    libpulseaudio
  ];

  enableParallelBuilding = true;

  # monologue.pro defines no install targets (upstream's bin/build only runs
  # qmake + make), so install by hand (matches pkgbuild/PKGBUILD: binary +
  # license + desktop file + scalable icon).
  installPhase = ''
    runHook preInstall
    install -Dm555 monologue "$out/bin/monologue"
    install -Dm644 LICENSE "$out/share/licenses/monologue/LICENSE"
    install -Dm644 pkgbuild/monologue.svg \
      "$out/share/icons/hicolor/scalable/apps/monologue.svg"
    install -Dm644 pkgbuild/monologue.desktop \
      "$out/share/applications/monologue.desktop"
    runHook postInstall
  '';

  meta = {
    description = "Simple, theme-synced webcam recorder (Omarchy app)";
    homepage = "https://github.com/omacom/monologue";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "monologue";
  };
})
