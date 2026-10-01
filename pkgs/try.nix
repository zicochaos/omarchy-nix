# try — "fresh directories for every vibe" (upstream-owned Omarchy component).
#
# Upstream: github.com/tobi/try — a Ruby CLI by Tobi Lütke (Shopify) for
# spinning up dated experiment/worktree directories with fuzzy search. Omarchy
# ships it as `try`. Stdlib-only Ruby (io/console, time, fileutils, set); the
# gem is published as `try-cli` but the repo install is just try.rb + lib/.
# We vendor the source tree and install try.rb next to its lib/ under
# share/try, so `require_relative 'lib/...'` resolves, with bin/try a wrapper
# exec'ing it. (Upstream's own flake.nix and Homebrew Formula put lib/ in
# bin/, which lands a stray bin/lib/ directory in every profile's bin.)
#
# Pinned to the latest release tag v1.10.1.
{
  lib,
  stdenv,
  fetchFromGitHub,
  ruby,
  bash,
  makeBinaryWrapper,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "try";
  version = "1.10.1";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "try";
    rev = "v${finalAttrs.version}";
    hash = "sha256-ZSt6LSp0AQTbdN86lJGJPWcx6oFR63AFi4s8Vjr5a5o=";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];
  buildInputs = [
    ruby
    bash
  ];

  # try.rb emits `/usr/bin/env ruby` (line-1 shebang + the two shell-init
  # emission sites) and `/usr/bin/env sh` (the two worktree-hook emission
  # sites) — all broken outside FHS. Rewrite every site to store paths;
  # patchShebangs then leaves the already-absolute line-1 shebang alone.
  postPatch = ''
    substituteInPlace try.rb \
      --replace-fail '/usr/bin/env ruby' '${ruby}/bin/ruby' \
      --replace-fail '/usr/bin/env sh' '${bash}/bin/sh'
  '';

  # No build step: try.rb is a Ruby script with `require_relative 'lib/...'`.
  # Install it with lib/ beside it so the relative requires resolve
  # (require_relative is relative to the calling file). The wrapper execs
  # the script by its store path, so $0 (which `try init` embeds in the
  # shell function it emits) is $out/share/try/try.rb.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/try
    install -Dm755 try.rb $out/share/try/try.rb
    cp -r lib $out/share/try/lib
    makeWrapper $out/share/try/try.rb $out/bin/try \
      --prefix PATH : ${lib.makeBinPath [ ruby ]}
    runHook postInstall
  '';

  meta = {
    description = "Fresh directories for every vibe — manage experiment/worktree dirs (Omarchy component)";
    homepage = "https://github.com/tobi/try";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "try";
  };
})
