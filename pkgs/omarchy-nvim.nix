# omarchy-nvim — the Omarchy LazyVim starter Neovim configuration.
#
# Upstream packages this from github.com/omacom-io/omarchy-pkgs
# (pkgbuilds/omarchy-nvim). The PKGBUILD composes the config from two sources:
#   1. github.com/LazyVim/starter  — the LazyVim template (branch `main`; no
#      release tags exist).
#   2. an Omarchy overlay shipped inside omarchy-pkgs itself: lua/, plugin/,
#      lazyvim.json (extra + override config) plus an omarchy-nvim-setup helper
#      that seeds a user's ~/.config/nvim from the packaged tree.
#
# What upstream ALSO does, and this derivation deliberately does NOT: pre-build
# the Lazy plugin cache by running `nvim --headless "+Lazy! sync"` with network
# access during packaging (~88 MiB into /etc/skel). The Nix build sandbox
# forbids network, so that cache is not reproducible here. This derivation
# ships the config tree + setup helper only; lazy.nvim bootstraps and installs
# plugins on the first `nvim` launch (the LazyVim starter default behaviour).
#
# Installed layout (mirrors pacman's /usr/share/omarchy-nvim under $out):
#   $out/share/omarchy-nvim/config   LazyVim starter + Omarchy overlay
#   $out/share/omarchy-nvim/data     empty (placeholder; seeded by lazy at runtime)
#   $out/bin/omarchy-nvim-setup      seeds ~/.config/nvim from the config tree
#
# stdenvNoCC: Lua config + a bash helper, no compilation.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

let
  # Mirrors pkgver from the upstream PKGBUILD; bump together with the revs.
  version = "2026.7.27";

  # LazyVim template (branch `main` — upstream has no release tags).
  starter = fetchFromGitHub {
    owner = "LazyVim";
    repo = "starter";
    rev = "803bc181d7c0d6d5eeba9274d9be49b287294d99";
    hash = "sha256-QrpnlDD4r1X4C8PqBhQ+S3ar5C+qDrU1Jm/lPqyMIFM=";
  };

  # Omarchy's packaging repo; only pkgbuilds/omarchy-nvim/ is consumed.
  omarchyPkgs = fetchFromGitHub {
    owner = "omacom-io";
    repo = "omarchy-pkgs";
    rev = "0a80091fe638ff13e894a4c1c4a88f4a460207ea";
    hash = "sha256-3Be7nGxjQiJHWI1f694X4mtxGyt/4c//CakQE1q0EcU=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "omarchy-nvim";
  inherit version;

  src = starter;

  # The Omarchy overlay (lua/, plugin/, lazyvim.json, omarchy-nvim-setup)
  # lives in the second source; consume it by store path rather than as `src`.
  omarchyOverlay = "${omarchyPkgs}/pkgbuilds/omarchy-nvim";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest="$out/share/omarchy-nvim"
    ov="$omarchyOverlay"

    # --- config tree: LazyVim starter + Omarchy overlay (mirrors PKGBUILD) ---
    # `cp -a . <nonexistent>` makes <dest> a copy of the starter tree.
    mkdir -p "$dest"
    cp -a . "$dest/config"

    # `cp -r <dir> <existing-dir-with-same-name>/` merges under GNU cp, matching
    # the PKGBUILD's `cp -r "$startdir/lua" "$XDG_CONFIG_HOME/nvim/"`. The
    # overlay's lua/config/options.lua overwrites the starter's; the rest
    # (remote_clipboard, all-themes, theme-hotreload, snacks, transparency) is
    # additive.
    cp -r "$ov/lua" "$dest/config/"
    cp -r "$ov/plugin" "$dest/config/"
    cp "$ov/lazyvim.json" "$dest/config/"

    # Upstream keeps an empty data/site after dropping the prebuilt cache;
    # mirror it so omarchy-nvim-setup's DATA_SOURCE_DIR resolves (plugins are
    # bootstrapped by lazy.nvim at runtime — see header).
    mkdir -p "$dest/data/site"

    # --- omarchy-nvim-setup: NixOS path adaptation ---
    # Repoint the three hardcoded source paths at this derivation's output.
    # NixOS has no /etc/skel populated by packages; the vendored config tree
    # under $out is the seed source. The rest of the script runs unchanged
    # (config copy, theme.lua symlink, xdg-mime defaults).
    #
    # copy_tree: the nix store is read-only (files 444, dirs 555). `cp -a`
    # preserves those modes into $HOME, which then blocks the theme.lua symlink
    # (read-only lua/plugins/) and any later user edits. Add --no-preserve=mode
    # — same fix omarchy.nix applies to its store->$HOME copies.
    mkdir -p "$out/bin"
    substitute "$ov/omarchy-nvim-setup" "$out/bin/omarchy-nvim-setup" \
      --replace-fail 'PACKAGE_DIR="/usr/share/omarchy-nvim"' "PACKAGE_DIR=\"$dest\"" \
      --replace-fail 'SKEL_CONFIG_DIR="/etc/skel/.config/nvim"' "SKEL_CONFIG_DIR=\"$dest/config\"" \
      --replace-fail 'SKEL_DATA_DIR="/etc/skel/.local/share/nvim"' "SKEL_DATA_DIR=\"$dest/data\"" \
      --replace-fail 'cp -a "$src" "$dest"' 'cp -a --no-preserve=mode "$src" "$dest"'
    chmod 755 "$out/bin/omarchy-nvim-setup"

    runHook postInstall
  '';

  meta = {
    description = "Omarchy LazyVim starter Neovim configuration";
    longDescription = ''
      The Neovim configuration Omarchy ships: the LazyVim starter with an
      Omarchy overlay (extra themes, remote clipboard, transparency, hot theme
      reload). Unlike the Arch package, this Nix derivation does not pre-build
      the Lazy plugin cache; lazy.nvim installs plugins on first launch.
    '';
    homepage = "https://github.com/omacom-io/omarchy-pkgs/tree/master/pkgbuilds/omarchy-nvim";
    # Starter is Apache-2.0; the Omarchy overlay is MIT.
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux;
    mainProgram = "omarchy-nvim-setup";
    outputsToInstall = [ "out" ];
  };
})
