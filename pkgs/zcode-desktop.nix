# ZCode desktop app (Z.ai) — the vendor ships Linux exclusively as a Debian
# package from its own CDN, so this derivation unpacks the .deb and wraps the
# Electron tree: the same vendor-artifact approach as claude-desktop here and
# as upstream Omarchy's AUR package `z-code-bin` (whose name the catalog
# entry's `arch` mirrors). Not in nixpkgs at this pin. Unfree (Z.ai's EULA).
#
# The app is two entry points: `zcode-desktop` (the GUI) and `zcode` (the CLI
# the app bundles — upstream runs it as Electron in node mode). The
# electron-updater metadata is removed: on NixOS the app lives in the store,
# so updates come from the flake, never from an in-app package manager.
#
# Known upstream behaviour, documented rather than patched away: on every
# start the app's deep-link module checks $XDG_DATA_DIRS for a system
# applications/zcode.desktop. When one is visible (any install through the
# catalog provides it), the app deletes a leftover user-level
# ~/.local/share/applications/zcode.desktop — but only if the file carries
# its own marker line `Comment=ZCode Desktop App`; a same-named file without
# the marker is kept and shadows the packaged entry. When no system entry
# exists, the app writes the user-level file itself, with Exec set to the
# running binary's absolute path: for a non-installed copy (a build output,
# a `nix run`, a test harness) that is the un-wrapped binary inside the
# store path (<store-path>/opt/ZCode/zcode), missing this wrapper's
# environment, and the entry can dangle once that store path is
# garbage-collected. Anything running the app from a build output should
# clean that user-level file up afterwards.
#
# Bump: version + hash from
# https://cdn-zcode.z.ai/zcode/electron/releases/<version>/linux-x64/ZCode-<version>-linux-x64.deb
# — the current version is the one on https://zcode.z.ai/en#all-downloads
# (the AUR z-code-bin PKGBUILD pins the same artifacts but lags releases;
# 3.14.0 shipped on the downloads page while the AUR was still at 3.12.3).
# Upstream also ships linux-arm64 for when the port gains aarch64.
{
  lib,
  stdenv,
  fetchurl,
  git,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  xdg-utils,

  ### Electron/Chromium runtime
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxscrnsaver,
  libxtst,
  libxcrypt-legacy,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "zcode-desktop";
  version = "3.14.0";

  src = fetchurl {
    # Upstream moved the deb under <version>/linux-x64/ as of 3.3.x.
    url = "https://cdn-zcode.z.ai/zcode/electron/releases/${finalAttrs.version}/linux-x64/ZCode-${finalAttrs.version}-linux-x64.deb";
    sha256 = "0al428hr9jgiryp9scy4g05kbva1m6vqnwx8srsdwrq9siv7y75d";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    glib
    gtk3
    gdk-pixbuf
    pango
    cairo
    atk
    at-spi2-atk
    at-spi2-core
    nss
    nspr
    dbus
    cups
    expat
    libdrm
    libgbm
    alsa-lib
    libnotify
    libsecret
    libuuid
    libxkbcommon
    libglvnd
    systemd
    wayland
    zlib
    libxcrypt-legacy
    stdenv.cc.cc.lib
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxcb
    libxscrnsaver
    libxtst
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/opt" "$out/bin" "$out/share"
    cp -r source/opt/ZCode "$out/opt/"
    cp -r source/usr/share/icons "$out/share/"
    install -Dm0644 source/usr/share/applications/zcode.desktop "$out/share/applications/zcode.desktop"

    # Upstream ships electron-updater metadata for deb/AppImage self-updates.
    # On NixOS the app lives in /nix/store, so updates must be handled by Nix,
    # not by an in-app package manager flow.
    rm -f "$out/opt/ZCode/resources/app-update.yml" "$out/opt/ZCode/resources/package-type"

    # Same password-store pin the port gives chromium (migration 1784508556):
    # on Hyprland and other non-GNOME sessions the embedded Chromium does not
    # auto-select the Secret Service backend. GPU libs via /run/opengl-driver
    # like claude-desktop; git rides the PATH for the bundled CLI, a coding
    # agent that shells out to it.
    makeWrapper "$out/opt/ZCode/zcode" "$out/bin/zcode-desktop" \
      --prefix PATH : ${
        lib.makeBinPath [
          xdg-utils
          git
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libsecret
          libglvnd
        ]
      } \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
      --add-flags "--password-store=gnome-libsecret"

    makeWrapper "$out/opt/ZCode/zcode" "$out/bin/zcode" \
      --set ELECTRON_RUN_AS_NODE 1 \
      --add-flags "$out/opt/ZCode/resources/glm/zcode.cjs"

    substituteInPlace "$out/share/applications/zcode.desktop" \
      --replace-fail 'Exec=/opt/ZCode/zcode %U' 'Exec=zcode-desktop %U'

    runHook postInstall
  '';

  meta = {
    description = "ZCode desktop app repackaged from the vendor's Linux deb";
    homepage = "https://zcode.z.ai/en";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "zcode-desktop";
  };
})
