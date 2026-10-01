# Builds every flake-owned package the Install menu can select
# (omarchy.ownedPackages: claude-desktop, omp, zcode-desktop,
# hermes-agent). catalog-consistency only evaluates their drvPaths, so a
# dead vendor URL, a stale fetch hash or an autoPatchelf break after a
# nixpkgs bump would otherwise first surface as a failed Install rebuild
# on a user's machine. omp's own installCheck runs as part of its build.
{
  pkgs,
  ownedPackages,
  ...
}:
pkgs.linkFarm "omarchy-owned-packages" (
  pkgs.lib.mapAttrsToList (name: path: { inherit name path; }) ownedPackages
)
