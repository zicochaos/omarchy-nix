# try — "fresh directories for every vibe" (upstream-owned Omarchy component).
#
# Upstream: github.com/tobi/try — a Ruby CLI by Tobi Lütke (Shopify) for
# spinning up dated experiment/worktree directories with fuzzy search. Omarchy
# ships it as `try`. Stdlib-only Ruby (io/console, time, fileutils, set); the
# gem is published as `try-cli` but the repo install is just try.rb + lib/.
# We vendor the source tree and install try.rb as `try` next to its lib/, so
# `require_relative 'lib/...'` resolves — matching upstream's own flake.nix
# and Homebrew Formula layout.
#
# Pinned to the latest release tag v1.9.3.
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
  version = "1.9.3";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "try";
    rev = "v${finalAttrs.version}";
    hash = "sha256-yDPQAI/3M1AFsNxBklM5lq8uQwHPr6ryZJBgC2aXGfQ=";
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
  # Install it as `try` in $out/bin with lib/ beside it so the relative
  # requires resolve (require_relative is relative to the calling file).
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp try.rb $out/bin/try
    cp -r lib $out/bin/lib
    chmod +x $out/bin/try
    wrapProgram $out/bin/try --prefix PATH : ${lib.makeBinPath [ ruby ]}
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
