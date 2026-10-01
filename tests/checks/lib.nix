# Helpers shared by more than one flake check (see default.nix).
{
  self,
  inputs,
  pkgs,
}:
{
  # testers.nixosTest calls the test module as `lib.toFunction test pkgs`,
  # so it can only pass `pkgs`. Apply the function here (closure) to hand
  # each test the flake modules it imports (self + home-manager), then
  # pass the resulting record. See tests/desktop.nix + tests/ux.nix.
  loadTest =
    file:
    (import file) {
      inherit pkgs;
      lib = pkgs.lib;
      omarchy = self;
      home-manager = inputs.home-manager;
    };
  # The omarchy-options.nix loader written by omarchy-nix-add on the
  # first opt: pick. Single source of truth: the pkglib template in
  # pkgs/omarchy.nix must stay byte-identical (enforced by
  # checks.omarchy-nix-transactions, omarchy-nix-transactions.nix), and
  # checks.omarchy-managed-options (omarchy-managed-options.nix) imports
  # this copy to prove the generated file actually folds picks into a
  # real NixOS evaluation.
  optLoaderGolden = pkgs.writeText "omarchy-options.nix" ''
    # Managed by omarchy-nix — omarchy-nix-search "opt:" picks land in
    # omarchy-options.json next to this file; this loader folds them into
    # your NixOS configuration. Generated once by omarchy-nix-add; do not
    # edit. Import it from your flake (README: "Menu-set NixOS options"):
    #   imports = [ omarchy-nix.nixosModules.default ]
    #     ++ (if builtins.pathExists ./omarchy-options.nix then [ ./omarchy-options.nix ] else [ ]);
    # Delete both files to clear every pick.
    { lib, ... }:
    let
      json = builtins.fromJSON (builtins.readFile ./omarchy-options.json);
      option = path: value: lib.setAttrByPath (lib.splitString "." path) value;
    in
    {
      config = lib.mkIf (json != { }) (lib.mkMerge (lib.mapAttrsToList option json));
    }
  '';
}
