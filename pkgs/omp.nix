# omp (Oh My Pi) — coding agent with the IDE wired in (can1357/oh-my-pi,
# MIT). Upstream Omarchy installs it as a mise tool; the mise model is
# rejected here, so this ships the release binary. Upstream's own flake
# builds from source through bun2nix; that machinery (and its unstable
# nixpkgs pin) is not worth carrying for the same binary.
#
# The release ELF is a bun single-executable-application: the app is
# appended after the ELF structures and located via file offsets. Any ELF
# rewrite breaks it — autoPatchelf grew the file by ~1 KiB and shifted the
# payload, after which the binary fell back to plain-bun behavior
# (`omp --version` printed Bun's, `omp` printed bun's help; measured
# 2026-09-19 on the 66.247 VM right after a menu install). The raw binary
# plus the nixpkgs glibc loader works verbatim, so the derivation ships the
# binary UNTOUCHED and bin/omp is an exec wrapper that invokes it through
# the loader explicitly — no interpreter rewrite, no strip, no patchelf.
#
# Bump: version + hash from the release's SHA256SUMS.txt
# https://github.com/can1357/oh-my-pi/releases
{
  lib,
  stdenv,
  fetchurl,
  glibc,
  makeBinaryWrapper,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omp";
  version = "18.2.6";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${finalAttrs.version}/omp-linux-x64";
    sha256 = "18j7jbpqxbzii5yy1hrczc9z4lcxk71iw5bzw36dh8z8j665jf0g";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontUnpack = true;
  # The SEA payload is offset-keyed: keep the ELF byte-identical to the
  # release artifact (see the header comment).
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/omp.bin
    makeWrapper ${glibc}/lib/ld-linux-x86-64.so.2 $out/bin/omp \
      --add-flags "$out/libexec/omp.bin"

    runHook postInstall
  '';

  # Behavioral gate for the packaging scheme above: the binary must answer
  # with omp's own version, not Bun's — the exact failure mode this
  # derivation existed in before the loader-wrapper fix.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    [[ "$($out/bin/omp --version)" == "omp/${finalAttrs.version}" ]] || {
      echo "installCheck: omp --version did not print omp/${finalAttrs.version} — the SEA payload is not loading (bun fallback?)" >&2
      exit 1
    }
    runHook postInstallCheck
  '';

  meta = {
    description = "Coding agent with the IDE wired in";
    homepage = "https://github.com/can1357/oh-my-pi";
    license = lib.licenses.mit;
    mainProgram = "omp";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
