# omacalc — upstream-owned Omarchy app: a simple calculator.
# Qt6 Quick/QML app built with qmake6 (see omacalc.pro); compiles to a single
# `omacalc` executable with the QML and fonts embedded via Qt resources.
{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omacalc";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omacalc";
    rev = "v${finalAttrs.version}";
    hash = "sha256-I+WxkMz/2hCf4OpJKu99+30c0CxyxFD0M6eSLFDLs1I=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative # includes Qt Quick Controls 2 (merged in Qt 6.2)
  ];

  enableParallelBuilding = true;

  # omacalc.pro defines no install targets, so install the built binary by hand.
  installPhase = ''
    runHook preInstall
    install -Dm555 omacalc "$out/bin/omacalc"
    runHook postInstall
  '';

  meta = {
    description = "Simple calculator (Omarchy app)";
    homepage = "https://github.com/omacom/omacalc";
    # MIT (app) + OFL-1.1 (the embedded fonts), as the omarchy-pkgs PKGBUILD declares.
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    platforms = lib.platforms.linux;
    mainProgram = "omacalc";
  };
})
