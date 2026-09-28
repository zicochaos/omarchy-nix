# herdr — upstream-owned Omarchy binary: a terminal workspace manager for
# AI coding agents (tmux-alike shipped alongside tmux since v4.0.0; SUPER+CTRL+RETURN
# opens it, `alias h=herdr`, `hdl/hds/hdlm/hsl` dev-layout helpers).
# Vendored because nixpkgs does not ship a herdr package (checked 2026-08-18
# against the 26.05 pin and unstable). The vendored omarchy tree seeds its
# config via omarchy-refresh-config herdr/config.toml; nothing else to wire.
#
# Source: herdrdev/herdr (the project moved there from omacom-io/herdr; the
# Omarchy PKGBUILD builds herdrdev v0.9.1 since the 349ecc0 bump, and
# omarchy-theme-set-herdr-machines needs its `herdr machine` subcommand).
#
# Build mirrors upstream's own nix/package.nix: the Rust build script
# compiles the vendored libghostty-vt terminal parser with Zig 0.16, feeding
# it the zon dependencies as a --system dir (build.zig.zon.nix is generated
# by zon2nix and shipped in the repo) so the sandbox build never fetches.
# Zig is only referenced through $ZIG, not put on nativeBuildInputs, so its
# setup hook never replaces cargo's build phase.
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
  version = "0.9.1";

  src = fetchFromGitHub {
    owner = "herdrdev";
    repo = "herdr";
    rev = "v${version}";
    hash = "sha256-N6+kprfWRyh0AkAiopkGsNXUGGORyPVFHEaDHCpGQs8=";
  };

  zigDeps = callPackage "${src}/vendor/libghostty-vt/build.zig.zon.nix" {
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

  cargoLock.lockFile = "${src}/Cargo.lock";

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
