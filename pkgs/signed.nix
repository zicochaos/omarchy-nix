# signed — upstream-owned Omarchy app: sign PDFs and fill them in with text
# and dates (replaced Xournal++ in the upstream base packages at 33783b1).
# Qt6 Quick/QML app built with qmake6 (see signed.pro, `link_pkgconfig`
# against poppler-qt6 + libqpdf); compiles to a single `signed` executable.
# xdg-desktop-portal (file picker) is a runtime concern — the portal the
# desktop already runs, not a build or runtime library here.
{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  qt6,
  poppler,
  qpdf,
  nss,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "signed";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "signed";
    rev = "v${finalAttrs.version}";
    hash = "sha256-fH5jXdO0uNsRblramzU0lcP3Dvv7pMZjf41FdE3lKjY=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative # includes Qt Quick Controls 2 (merged in Qt 6.2)
    qt6.qtwayland
    # The pin's default poppler attr builds the glib variant; signed needs
    # the Qt6 one (poppler-qt6.pc via link_pkgconfig), with the same qtbase
    # the app links.
    (poppler.override {
      qt6Support = true;
      qtbase = qt6.qtbase;
    })
    qpdf
    nss
  ];

  enableParallelBuilding = true;

  # signed.pro defines no install targets, so install by hand (matches
  # pkgbuild/PKGBUILD: binary + desktop file + scalable icon).
  installPhase = ''
    runHook preInstall
    install -Dm555 signed "$out/bin/signed"
    install -Dm644 pkgbuild/signed.svg \
      "$out/share/icons/hicolor/scalable/apps/signed.svg"
    install -Dm644 pkgbuild/signed.desktop \
      "$out/share/applications/signed.desktop"
    runHook postInstall
  '';

  meta = {
    description = "Sign PDFs and fill them in with text and dates (Omarchy app)";
    homepage = "https://github.com/omacom/signed";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "signed";
  };
})
