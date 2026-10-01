# herdr — upstream-owned Omarchy binary: a terminal workspace manager for
# AI coding agents (tmux-alike shipped alongside tmux since v4.0.0; SUPER+CTRL+RETURN
# opens it, `alias h=herdr`, `hdl/hds/hdlm/hsl` dev-layout helpers).
# Vendored because nixpkgs does not ship a herdr package (checked 2026-08-18
# against the 26.05 pin and unstable). The vendored omarchy tree seeds its
# config via omarchy-refresh-config herdr/config.toml; nothing else to wire.
#
# Source: herdrdev/herdr (the project moved there from omacom-io/herdr; the
# Omarchy PKGBUILD builds herdrdev v0.9.1 since the 349ecc0 bump — this pin
# may run ahead of it — and omarchy-theme-set-herdr-machines needs its
# `herdr machine` subcommand).
#
# Build mirrors upstream's own nix/package.nix: the Rust build script
# compiles the vendored libghostty-vt terminal parser with Zig 0.16, feeding
# it the zon dependencies as a --system dir so the sandbox build never
# fetches. Zig is only referenced through $ZIG, not put on
# nativeBuildInputs, so its setup hook never replaces cargo's build phase.
#
# No import-from-derivation: upstream's package.nix reads Cargo.lock and
# vendor/libghostty-vt/build.zig.zon.nix out of the source tree, which from
# a fetched src is IFD (`.#herdr` and every host config would then fail
# under allow-import-from-derivation = false). Here the crates come from
# cargoHash (fetchCargoVendor) and the zon2nix file is a committed copy,
# pkgs/herdr-zig-deps.nix.
#
# Bump: set version, then
#   1. hash: `nix flake prefetch --json github:herdrdev/herdr/v<version>`
#      (the "hash" field; "storePath" is the unpacked tree for step 2);
#   2. zig deps: replace everything below the header comment of
#      pkgs/herdr-zig-deps.nix with
#      <storePath>/vendor/libghostty-vt/build.zig.zon.nix, update the
#      version named in that header, then `nix fmt`;
#   3. cargoHash: set to lib.fakeHash, `nix build .#herdr`, paste the
#      reported hash.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  callPackage,
  runCommand,
  zig_0_16,
  zstd,
  pkg-config,
  git,
}:

let
  version = "0.9.3";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr";
    tag = "v${version}";
    hash = "sha256-uu452Xe23pSvFk7w7fKPjiaqY5QenUIljao2SFAxpc0=";
  };

  zigDeps = callPackage ./herdr-zig-deps.nix {
    name = "herdr-libghostty-vt-zig-cache";
    inherit zstd;
    # linkFarm flattened to a single output dir, as upstream's
    # nix/package.nix does (cp -rL of every entry under $out/<name>).
    linkFarm =
      name: entries:
      runCommand name { } ''
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (entry: ''
          cp -rL ${entry.path} $out/${entry.name}
        '') entries}
      '';
  };
in
rustPlatform.buildRustPackage {
  pname = "herdr";
  inherit version src;

  cargoHash = "sha256-+gTWtEheyuI59yf2PqRbcbcFIW+/cYb7zZ2mPv2VN0Y=";

  nativeBuildInputs = [
    git
    pkg-config
  ];

  env = {
    LIBGHOSTTY_VT_OPTIMIZE = "ReleaseFast";
    LIBGHOSTTY_VT_SIMD = "true";
    LIBGHOSTTY_VT_ZIG_SYSTEM_DIR = zigDeps;
    ZIG = lib.getExe zig_0_16;
  };

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
  '';

  doCheck = false;

  meta = {
    description = "Terminal workspace manager for AI coding agents (Omarchy)";
    homepage = "https://herdr.dev";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "herdr";
  };
}
