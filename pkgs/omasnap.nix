# omasnap — Omarchy's native Wayland screenshot + annotation overlay.
# Qt6 Widgets C++ app built with CMake/Ninja (C++23): it talks to the
# compositor directly through the ext-image-copy-capture / wlr virtual
# pointer protocols, whose client bindings are generated at build time with
# wayland-scanner, and places its overlays via LayerShellQt. Pinned to
# release tag v1.21.0, the version omacom/omarchy-pkgs packages.
#
# Differs from the Arch PKGBUILD:
#   - CMakeLists hardcodes /usr/share/wayland-protocols for the ext-*
#     protocol XMLs; substituted with the nixpkgs wayland-protocols path.
#   - the check() smoke suite (omasnap-smoke) is not run in the sandbox
#     (it needs a writable XDG_RUNTIME_DIR and wall-clock settle windows),
#     so -DBUILD_TESTING=OFF skips building it entirely.
#
# Runtime tools invoked on PATH (mirrors the Arch depends list; the NixOS
# module already ships wl-clipboard + tesseract5 in runtimeDeps and hyprctl
# comes from the session compositor): hyprctl (compositor IPC, capture
# targeting + scroll injection), wl-copy/wl-paste (wl-clipboard), tesseract
# (OCR of selections, -l $OMASNAP_OCR_LANGS / $OMARCHY_OCR_LANGS, default
# eng — nixpkgs tesseract bundles share/tessdata/eng.traineddata, so no
# TESSDATA_PREFIX wrapper is needed) and omarchy-notification-send (capture
# notifications, provided by the omarchy package).
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  qt6,
  kdePackages,
  wayland,
  wayland-scanner,
  wayland-protocols,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omasnap";
  version = "1.21.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omasnap";
    rev = "v${finalAttrs.version}";
    hash = "sha256-kpoPb5F5yqcczBRUfENsEfv+BD67zQsTG9Ur6Bi3viE=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    # find_program(WAYLAND_SCANNER) in CMakeLists.txt.
    wayland-scanner
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    # Concurrent/Core/Gui/Test/Widgets are all qtbase. Qt 6.11 also ships the
    # whole Wayland *client* stack in qtbase (libQt6WaylandClient, the
    # libqwayland QPA plugin and the wayland-*-client integration plugins),
    # so qt6.qtwayland (compositor-side only) is not needed.
    qt6.qtbase
    # LayerShellQt::Interface (Qt6 flavor lives under kdePackages).
    kdePackages.layer-shell-qt
    # pkg_check_modules wayland-client.
    wayland
    # ext-foreign-toplevel-list / ext-image-capture-source /
    # ext-image-copy-capture XMLs (patched in below).
    wayland-protocols
  ];

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail "/usr/share/wayland-protocols" "${wayland-protocols}/share/wayland-protocols"
  '';

  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  # cmake --install already ships bin/omasnap, the bundled-font licenses and
  # the .desktop entry; add the README doc + top-level LICENSE like the
  # PKGBUILD does. The cmake hook runs install from the build directory, so
  # reference the docs through the source store path.
  postInstall = ''
    install -Dm644 "${finalAttrs.src}/README.md" "$out/share/doc/omasnap/README.md"
    install -Dm644 "${finalAttrs.src}/LICENSE" "$out/share/licenses/omasnap/LICENSE"
  '';

  meta = {
    description = "Native Wayland screenshot and annotation overlay for Hyprland (Omarchy app)";
    homepage = "https://github.com/omacom/omasnap";
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    platforms = lib.platforms.linux;
    mainProgram = "omasnap";
  };
})
