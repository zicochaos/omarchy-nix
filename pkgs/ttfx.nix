# ttfx — upstream-owned Omarchy binary: terminal text effects as a single
# dependency-free Rust binary. Rust port of TerminalTextEffects (TTE) that
# renders byte-identical frames and starts in ~1ms instead of TTE's ~107ms
# Python startup. Powers the Omarchy screensaver (bin/omarchy-screensaver
# runs `ttfx -i <branding file>` and pgrep/pkill-matches the comm name).
# Vendored because nixpkgs does not ship a ttfx package (checked 2026-08-18
# against unstable).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ttfx";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ZeWRyo9zturjRcH23SDgFOKoPOSY6nGMFzGeJAoDapk=";
  };

  cargoHash = "sha256-ntoj5bmAa9U2+3K1UX6HL0t6MjfCYQNe5LuiuNJ/CnY=";

  meta = {
    description = "Terminal text effects as a single static binary (Rust TTE port, Omarchy screensaver)";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ttfx";
  };
})
