# Claude Desktop app — Anthropic ships the Linux beta exclusively as a
# Debian package through their own APT repository, so this derivation
# unpacks the .deb and wraps the Electron tree: the same vendor-artifact
# approach upstream Omarchy's PKGBUILD takes in omacom/omarchy-pkgs (MIT).
# The nixpkgs packaging is pending in NixOS/nixpkgs#537215 — when it
# reaches the pin, the catalog entry switches to the nixpkgs attr and this
# derivation retires. Unfree (Anthropic's proprietary EULA).
#
# Cowork (the app's local-VM task runner) is deliberately not wired up: it
# probes Debian's OVMF/virtiofsd paths, and the asar patching to redirect
# them (done in the nixpkgs PR) is skipped here — every other feature
# works, the VM feature fails at use time.
#
# Bump: version + hash come from the vendor index
# https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,

  ### Electron/Chromium runtime
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libcap_ng,
  libdrm,
  libglvnd,
  libsecret,
  libseccomp,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  libxtst,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
  util-linux,

  ### Exec'd by the app / its bundled Claude Code
  bubblewrap,
  socat,
  xdg-utils,
  git,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-desktop";
  version = "1.52386.3";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${finalAttrs.version}_amd64.deb";
    hash = "sha256-eXWUzoHBnT9rU3P9uAFpnHVwFvVgBxX6F1HsNOhohFY=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng
    libdrm
    libglvnd
    libsecret
    libseccomp
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxtst
    mesa
    nspr
    nss
    pango
    systemd
    util-linux
  ];

  unpackPhase = ''
    runHook preUnpack

    dpkg-deb --fsys-tarfile $src | tar --extract

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    mv usr/* $out

    # Replace the Debian /usr/bin symlink with the Omarchy launcher (flags
    # file + Wayland Ozone pick) pointed at the store path.
    install -Dm755 ${./claude-desktop-launcher.sh} $out/bin/claude-desktop
    substituteInPlace $out/bin/claude-desktop \
      --replace-fail '__APP_BIN__' "$out/lib/claude-desktop/claude-desktop"

    runHook postInstall
  '';

  postFixup = ''
    # Same password-store pin the port gives chromium (migration 1784508556):
    # on Hyprland and other non-GNOME sessions Chromium does not auto-select
    # the Secret Service backend.
    wrapProgram $out/bin/claude-desktop \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          libsecret
          libglvnd
        ]
      } \
      --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
      --add-flags "--password-store=gnome-libsecret" \
      --prefix PATH : ${
        lib.makeBinPath [
          bubblewrap
          socat
          xdg-utils
          git
        ]
      }
  '';

  meta = {
    description = "Desktop application for Claude.ai";
    homepage = "https://claude.ai/download";
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
