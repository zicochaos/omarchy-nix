# First-party xAI Grok Build CLI. The nixpkgs grok-cli attribute is the
# unrelated superagent-ai API-key client; Omarchy's account dispatch needs
# xAI's `grok login`, GROK_HOME, and auth.json contract instead.
#
# Upstream installs mise's `grok` tool. Its registry resolves x.ai/cli/stable
# and downloads this vendor binary; 1.0.50 is the stable version selected
# for the f2a39c4 bump. Keep the binary untouched (static PIE) and suppress
# its updater with the documented process setting. Nix owns upgrades.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  installShellFiles,
  bash,
  coreutils,
  git,
  ripgrep,
  xdg-utils,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "grok-cli";
  version = "1.0.50";

  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${finalAttrs.version}-linux-x86_64";
    hash = "sha256-yA3gFVcG/y2ZViOIexAvLQq9LGKyZD3qOgzrr33XJNU=";
  };

  nativeBuildInputs = [
    makeWrapper
    installShellFiles
  ];

  dontUnpack = true;
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/libexec/grok"
    makeWrapper "$out/libexec/grok" "$out/bin/grok" \
      --set GROK_DISABLE_AUTOUPDATER 1 \
      --set-default SHELL ${bash}/bin/bash \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          coreutils
          git
          ripgrep
          xdg-utils
        ]
      }

    # The generators only render local command metadata. Isolate their
    # state from the builder's home; the same process setting suppresses
    # update checks for the installed command.
    export HOME="$TMPDIR/grok-completions-home"
    export GROK_HOME="$HOME/.grok"
    mkdir -p "$GROK_HOME"
    installShellCompletion --cmd grok \
      --bash <("$out/bin/grok" completions bash) \
      --fish <("$out/bin/grok" completions fish) \
      --zsh <("$out/bin/grok" completions zsh)

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/grok-check-home"
    export GROK_HOME="$HOME/.grok"
    mkdir -p "$GROK_HOME"
    versionOutput="$("$out/bin/grok" --version)"
    [[ "$versionOutput" == "grok ${finalAttrs.version} ("*")" ]]
    "$out/bin/grok" --help > help.txt
    "$out/bin/grok" login --help > login-help.txt
    grep -Fq 'login' help.txt
    grep -Fq 'Usage: grok login' login-help.txt
    runHook postInstallCheck
  '';

  meta = {
    description = "First-party xAI Grok coding agent with subscription account support";
    homepage = "https://x.ai/cli";
    # The official @xai-official/grok-linux-x64 platform package declares
    # Apache-2.0 for this binary (not the third-party nixpkgs package).
    license = lib.licenses.asl20;
    mainProgram = "grok";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
