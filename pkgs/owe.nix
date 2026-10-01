# owe — Omarchy Wallpaper Engine.
#
# Upstream (github.com/omacom/owe, MIT, C + one Qt6 QML plugin) ships three
# Wayland binaries — the `owed` daemon, the `owe` CLI and the `owe-render`
# child it supervises — plus `owe-lockfeed`, a Qt6 Quick QML plugin
# (qml-plugin/, module Owe.LockFeed) the Omarchy lock screen loads through a
# Loader so a missing module costs only the lock video. nixpkgs does not
# package owe, so this derivation ports Arch's two packages
# (omacom/omarchy-pkgs: pkgbuilds/owe + pkgbuilds/owe-lockfeed, both
# from the same source tarball) into one $out: the plugin is useless
# without the daemon and the daemon's lock-screen feed without the plugin.
#
# What the package must provide for Omarchy (vendored tree expectations):
#   - bin/owed, bin/owe, bin/owe-render, bin/owe-idle
#   - lib/systemd/user/owed.service (enabled by
#     install/user/first-run/enable-user-units.sh and migrations/1789764927.sh;
#     the nixpkgs systemd setup hook relocates the file to
#     share/systemd/user and leaves lib/systemd/user a symlink — both paths
#     resolve, and systemd.packages finds it)
#   - share/owe/10-owe-sync, the theme-set hook those scripts install via
#     `omarchy-hook-install theme-set /usr/share/owe/10-owe-sync` (they copy
#     it to ~/.config/omarchy/hooks/theme-set.d/). The path Omarchy passes is
#     the Arch one; the NixOS module owns mapping it to this package.
#   - lib/qt-6/qml/Owe/LockFeed/ (nixpkgs Qt layout; upstream's cmake install
#     dir is lib/qt6/qml). The shell finds it via
#     QT_ADDITIONAL_PACKAGES_PREFIX_PATH=$out or QML2_IMPORT_PATH.
#
# Runtime deps of scripts/binaries spawned by name (posix_spawnp / plain
# PATH lookup): ffmpeg and omarchy-shell (from `owed`), omarchy-theme-bg-next
# (from `owe`), socat (from the two hook scripts). ffmpeg and owe-idle's
# socat are wired in below; the copied theme-set hook, the two omarchy-*
# commands and socat come from the session PATH the NixOS module sets.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  cmake,
  makeWrapper,
  wayland-scanner,
  wayland,
  libGL,
  libepoxy,
  mpv,
  ffmpeg,
  systemd,
  qt6,
  socat,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "owe";
  version = "0.2.8";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "owe";
    rev = "v${finalAttrs.version}";
    hash = "sha256-2GfzL66OQ2r7UwBQ09dSFW2pw6wH84+m1VsBBvyxIaA=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    cmake
    makeWrapper
    wayland-scanner
  ];

  buildInputs = [
    # meson side (gl.pc/egl.pc/glesv2.pc come from libglvnd via libGL)
    wayland # wayland-client, wayland-egl
    libGL
    libepoxy
    mpv # libmpv (mpv.pc)
    ffmpeg # libavformat/libavcodec/libavutil/libswscale
    systemd # libsystemd
    # cmake side (qml-plugin)
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # wayland-protocols is deliberately absent: upstream's meson.build declares
  # it `required: false` and never uses it — the four protocol XMLs it
  # compiles are vendored in protocols/.

  # Nothing Qt-runnable ships here (the plugin is loaded in-process by the
  # Quickshell binary, which owns its own Qt environment), so skip the
  # qtbase wrap hook.
  dontWrapQtApps = true;

  # owe builds twice from one tree (mirrors the two Arch packages): the C
  # binaries go through the standard meson phases, and the QML plugin is
  # configured/built/installed alongside them from qml-plugin/.
  #
  # cmake is on nativeBuildInputs only for those hand-run qml-plugin calls,
  # so its setup hook must not claim the configure phase; meson's does (it
  # only won by hook order before this was explicit).
  dontUseCmakeConfigure = true;

  postConfigure = ''
    cmake -S "${finalAttrs.src}/qml-plugin" -B build-qml \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=$out \
      -DCMAKE_INSTALL_LIBDIR=lib
  '';

  postBuild = ''
    cmake --build build-qml
  '';

  postInstall = ''
    cmake --install build-qml

    # Relocate the plugin from cmake's lib/qt6/qml to the nixpkgs Qt layout
    # (lib/qt-6/qml, where qtdeclarative's own modules live), so
    # QT_ADDITIONAL_PACKAGES_PREFIX_PATH=$out resolves it.
    mkdir -p "$out/lib/qt-6/qml"
    mv "$out/lib/qt6/qml/Owe" "$out/lib/qt-6/qml/"
    rm -rf "$out/lib/qt6"

    # User unit: upstream points ExecStart at %h/.local/bin/owed; Arch seds
    # that to /usr/bin/owed. Here it goes to the store binary.
    install -Dm644 "${finalAttrs.src}/systemd/owed.service" "$out/lib/systemd/user/owed.service"
    substituteInPlace "$out/lib/systemd/user/owed.service" \
      --replace-fail '%h/.local/bin/owed' "$out/bin/owed"

    # hypridle hook (Arch: /usr/bin/owe-idle) and the theme-set hook
    # (Arch: /usr/share/owe/10-owe-sync; installed 644 — omarchy-hook-install
    # chmods its copy 755).
    install -Dm755 "${finalAttrs.src}/hooks/owe-idle" "$out/bin/owe-idle"
    install -Dm644 "${finalAttrs.src}/hooks/theme-set.d/10-owe-sync" "$out/share/owe/10-owe-sync"
    install -Dm644 "${finalAttrs.src}/config/config.toml" \
      "$out/share/doc/owe/config.toml.example"

    # owe-idle stays in the store, so it can pin socat. 10-owe-sync is
    # copied into ~/.config/omarchy/hooks/ and would keep a store path past
    # garbage collection; it keeps bare `socat`, which the omarchy module
    # ships on the system PATH.
    substituteInPlace "$out/bin/owe-idle" \
      --replace-fail '| socat -' "| ${socat}/bin/socat -"
    patchShebangs "$out/bin/owe-idle"
  '';

  # owed transcodes GIF/oversized sources and builds battery posters by
  # spawning `ffmpeg` from its own environment (posix_spawnp), so give the
  # daemon — and the owe-render child it supervises, which inherits the env —
  # a PATH that has it. owe-render is located as a sibling of
  # /proc/self/exe, which still lands in $out/bin after the wrap.
  postFixup = ''
    wrapProgram "$out/bin/owed" \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}
  '';

  # Arch runs `meson test` in check(); skipped here — the suite's GL tests
  # (transition, egl-context) need a rendering GL context the sandbox does
  # not provide.

  meta = {
    description = "Wallpaper engine for Omarchy (video/GIF/still backgrounds) with the lock-screen video feed QML module";
    homepage = "https://github.com/omacom/owe";
    # The repo ships no LICENSE file; MIT is what the omarchy-pkgs PKGBUILD declares.
    license = lib.licenses.mit;
    mainProgram = "owed";
    platforms = lib.platforms.linux;
  };
})
