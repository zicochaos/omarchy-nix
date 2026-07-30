# omawrite — distraction-free Markdown writer (upstream Omarchy app).
#
# Upstream: github.com/omacom-io/omawrite — Qt Quick + C++ app built with
# qmake (omawrite.pro). Pinned to release tag v0.4.0 (tags exist since v0.2.1).
#
# Qt modules from omawrite.pro:
#   core gui widgets printsupport dbus -> qtbase
#   qml quick quickcontrols2           -> qtdeclarative (merged in Qt6)
#   quickdialogs2                      -> qtdeclarative (merged in Qt6)
#
# Runtime: xdg-desktop-portal + a portal backend for the file/print pickers.
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omawrite";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom-io";
    repo = "omawrite";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Da8O2VlyDMNInxmQ8VvGOVnDWdmn27JIweBX4DWUPsg=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  # core/gui/widgets/printsupport/dbus -> qtbase
  # qml/quick/quickcontrols2/quickdialogs2 -> qtdeclarative (merged in Qt6)
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  postInstall = ''
    # qmake produces the binary at the source root; install it manually.
    install -Dm555 omawrite "$out/bin/omawrite"

    # Desktop integration (matches pkgbuild/ layout).
    install -Dm644 pkgbuild/omawrite.svg \
      "$out/share/icons/hicolor/scalable/apps/omawrite.svg"
    install -Dm644 pkgbuild/omawrite.desktop \
      "$out/share/applications/omawrite.desktop"

    # Licenses: MIT (app) + OFL-1.1 (bundled iA Writer Mono font).
    install -Dm644 LICENSE "$out/share/licenses/omawrite/LICENSE"
    install -Dm644 fonts/OFL.txt "$out/share/licenses/omawrite/OFL.txt"
  '';

  meta = {
    description = "Dead-simple Markdown writing app built with Qt Quick (Omarchy app)";
    homepage = "https://github.com/omacom-io/omawrite";
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    platforms = lib.platforms.linux;
    mainProgram = "omawrite";
  };
})
