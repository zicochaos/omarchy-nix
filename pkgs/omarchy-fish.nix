# Omarchy shell configuration for Fish (upstream: omacom-io/omarchy-fish),
# vendored as an opt-in profile.
#
# Pin: temporarily the zicochaos/omarchy-fish fork rev carrying PR
# omacom-io/omarchy-fish#7 (Quattro bash parity: cy/mup/rsw/lsw/dsw/tds
# helpers, cx alignment, ff Kitty branch, ~/.local/bin in PATH, lazy
# `try init`, the `# omarchy:args=` completion contract, zoxide cd
# history fix). Upstream merge latency is high (their PR #6 has waited
# since 2026-05), so the pin tracks the fork until an upstream release
# contains PR #7 — see docs/decisions/2026-07-31-fish-parity-fork-pin.md.
#
# Layout mirrors the canonical PKGBUILD
# (omacom-io/omarchy-pkgs/pkgbuilds/omarchy-fish): conf.d/functions/
# completions land in fish's vendor_* dirs, and fzf.fish v10.3 is bundled
# into the same dirs (never nixpkgs' newer fishPlugins.fzf-fish). Copy
# order matters: fzf.fish first, omarchy-fish second — both ship
# _fzf_search_history.fish and omarchy's version must win.
#
# Deviations:
#   - bin/omarchy-setup-fish is replaced by an informational stub:
#     upstream's script backs up ~/.bashrc and trampolines fish from bash,
#     which conflicts with the NixOS ownership model — the login shell is a
#     declarative account setting (users.users.<name>.shell).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  writeShellScript,
  writeText,
}:

let
  version = "1.5.0-unstable-2026-07-31";

  src = fetchFromGitHub {
    owner = "zicochaos";
    repo = "omarchy-fish";
    rev = "07fc8da701df1f8ec3ba6c2ef75119e14c4a16f7";
    hash = "sha256-nwSkPlumpBhvY1GZWtXRWaVXnDVftaPGIceO7AMEg3M=";
  };

  # Same fzf.fish revision the canonical PKGBUILD bundles.
  fzfSrc = fetchFromGitHub {
    owner = "PatrickF1";
    repo = "fzf.fish";
    rev = "refs/tags/v10.3";
    hash = "sha256-T8KYLA/r/gOKvAivKRoeqIwE2pINlxFQtZJHpOy9GMM=";
  };

  setupStub = writeShellScript "omarchy-setup-fish" ''
    cat <<'EOF'
    omarchy-fish on NixOS: the login shell is a declarative account
    setting, not something a script mutates.

    1. Enable the Omarchy Fish profile (installs fish + vendor files):

         omarchy.fish.enable = true;

    2. Pick fish as the login shell for your account:

         users.users.<name>.shell = pkgs.fish;

    3. Rebuild and log back in:

         sudo nixos-rebuild switch --flake <your-flake>

    The Omarchy Fish profile loads from the system profile's
    share/fish/vendor_* directories; nothing is copied to ~/.config/fish,
    and functions in ~/.config/fish/functions override the vendor ones.
    EOF
  '';

  # Bash parity gap filler: Quattro's bash profile gained
  # `alias a='omarchy-launch-agent --inline'` (default coding agent) after
  # the pinned fork rev. Port-level supplement until the fork picks it up —
  # drop this file when the pin advances past the fix.
  agentAliasFn = writeText "a.fish" ''
    function a --wraps omarchy-launch-agent --description 'Launch the default coding agent inline'
        omarchy-launch-agent --inline $argv
    end
  '';
in
stdenvNoCC.mkDerivation {
  pname = "omarchy-fish";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Vendor dirs — same targets as the PKGBUILD. dotglob so leading-dot
    # function names (....fish, .....fish) are not skipped.
    shopt -s dotglob
    install -dm755 "$out/share/fish/vendor_conf.d" \
      "$out/share/fish/vendor_functions.d" \
      "$out/share/fish/vendor_completions.d"
    for f in "${fzfSrc}/conf.d/"*.fish; do install -m644 "$f" "$out/share/fish/vendor_conf.d/"; done
    for f in "${fzfSrc}/functions/"*.fish; do install -m644 "$f" "$out/share/fish/vendor_functions.d/"; done
    for f in "${fzfSrc}/completions/"*.fish; do install -m644 "$f" "$out/share/fish/vendor_completions.d/"; done
    for f in conf.d/*.fish; do install -m644 "$f" "$out/share/fish/vendor_conf.d/"; done
    for f in functions/*.fish; do install -m644 "$f" "$out/share/fish/vendor_functions.d/"; done
    for f in completions/*.fish; do install -m644 "$f" "$out/share/fish/vendor_completions.d/"; done
    shopt -u dotglob

    # Docs + licenses (PKGBUILD layout).
    install -dm755 "$out/share/omarchy-fish"
    cp -r templates "$out/share/omarchy-fish/"
    install -m644 LICENSE README.md "$out/share/omarchy-fish/"
    install -m644 "${fzfSrc}/LICENSE.md" "$out/share/omarchy-fish/LICENSE.fzf.fish"
    install -m644 "${fzfSrc}/README.md" "$out/share/omarchy-fish/README.fzf.fish.md"

    # NixOS informational stub replaces upstream's mutating setup script.
    install -Dm755 "${setupStub}" "$out/bin/omarchy-setup-fish"

    # Port-level bash-parity supplement (see agentAliasFn in let).
    install -m644 "${agentAliasFn}" "$out/share/fish/vendor_functions.d/a.fish"

    runHook postInstall
  '';

  meta = {
    description = "Omarchy shell configuration for Fish (opt-in vendored profile)";
    homepage = "https://github.com/omacom-io/omarchy-fish";
    license = lib.licenses.mit;
    mainProgram = "omarchy-setup-fish";
    platforms = lib.platforms.linux;
  };
}
