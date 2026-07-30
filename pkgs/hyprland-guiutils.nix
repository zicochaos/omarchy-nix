# hyprwm/hyprland-guiutils — Hyprland GUI utilities (successor to
# hyprland-qtutils). CMake C++23 project producing five standalone GUI
# binaries (hyprland-dialog, -donate-screen, -run, -update-screen, -welcome)
# that render via the hypr ecosystem toolkit (hyprtoolkit + pixman/drm) rather
# than Qt. Pinned to the latest release tag; check the upstream CMakeLists
# pkg_check_modules list when bumping — required versions move with hyprland.
#
# Build-input set is wider than the upstream pkg_check_modules list: the hypr
# ecosystem libraries (hyprtoolkit/hyprgraphics/aquamarine) reference one
# another and cairo/pango/wayland/gbm in their *public* headers but do not
# declare them via pkg-config Requires.private, so each transitive include
# path must be present here. Mirrors the buildInputs of nixpkgs' hyprtoolkit.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  cairo,
  pango,
  wayland,
  wayland-protocols,
  libgbm,
  libglvnd,
  iniparser,
  hyprlang,
  hyprutils,
  hyprtoolkit,
  aquamarine,
  hyprgraphics,
  pixman,
  libxkbcommon,
  libdrm,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hyprland-guiutils";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "hyprwm";
    repo = "hyprland-guiutils";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Ee78BRFi+MrmgHmmW+2dZUEI1R3cssEzza0ar3fsNX8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    hyprlang
    hyprutils
    hyprtoolkit
    aquamarine
    hyprgraphics
    pixman
    libxkbcommon
    libdrm
    # Transitive includes pulled by hyprtoolkit/hyprgraphics public headers
    cairo
    pango
    wayland
    wayland-protocols
    libgbm
    libglvnd
    iniparser
  ];

  # The top-level CMakeLists runs `git rev-parse` at configure time to embed a
  # commit hash/branch into the binaries. fetchFromGitHub ships no .git and git
  # is absent from the build env, so those execute_process calls yield empty
  # strings (their results are not checked) and the binaries build without it.
  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Hyprland GUI utilities (dialog, run, welcome, update/donate screens)";
    homepage = "https://github.com/hyprwm/hyprland-guiutils";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    mainProgram = "hyprland-dialog";
  };
})
