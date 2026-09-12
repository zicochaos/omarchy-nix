# omp (Oh My Pi) — coding agent with the IDE wired in (can1357/oh-my-pi,
# MIT). Upstream Omarchy installs it as a mise tool; the mise model is
# rejected here, so this ships the release binary — a bun-compiled ELF
# that links only glibc basics (libc/pthread/dl), fine under
# autoPatchelfHook. The TypeScript/Bazel source build is not worth the
# maintenance for the same result.
#
# Bump: version + hash from the release's SHA256SUMS.txt
# https://github.com/can1357/oh-my-pi/releases
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omp";
  version = "18.1.18";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${finalAttrs.version}/omp-linux-x64";
    hash = "sha256-RUIfml8RK8R8ufd8S015J2Mfj/hZYk+CEofshU6yOfw=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/omp

    runHook postInstall
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
