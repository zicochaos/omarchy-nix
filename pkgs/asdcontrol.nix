# asdcontrol — Apple Studio Display (and Pro Display XDR) brightness control.
#
# A tiny single-file C++ tool that talks to the HID device over the linux
# hiddev ioctl interface. No runtime deps beyond glibc + kernel support for
# the monitor's /dev/usb/hiddevX node. Maintained here (not in nixpkgs) per
# the omarchy-nix convention of packaging upstream-owned apps under pkgs/.
{
  lib,
  stdenv,
  linuxHeaders,
  fetchFromGitHub,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "asdcontrol";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "omakasui";
    repo = "asdcontrol";
    # v0.6.0 tag (== default-branch HEAD at time of pinning).
    rev = "46fe08bf8251f37799c2833b0b194245530531a2";
    hash = "sha256-kxzkZeoUZu3dUp/E95h5e8R/BMLakyIgoSug2j0jOR4=";
  };

  # <linux/hiddev.h> and <asm/types.h> come from the kernel headers; linuxHeaders
  # is otherwise an implicit part of stdenv's libc, but we make the dependency
  # explicit so the build is reproducible across stdenv variants.
  buildInputs = [ linuxHeaders ];

  # Upstream Makefile: `g++ -O2 -Wall -Wextra asdcontrol.cpp -o asdcontrol`.
  # It hardcodes CXX=g++ (stdenv sets g++ to the wrapped compiler) and an install
  # target that copies to /usr/local/bin — we install to $out/bin ourselves.
  makeFlags = [ "asdcontrol" ];

  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 asdcontrol $out/bin/asdcontrol
    runHook postInstall
  '';

  meta = {
    description = "Apple Studio Display / Pro Display XDR brightness control for Linux";
    homepage = "https://github.com/omakasui/asdcontrol";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "asdcontrol";
  };
})
