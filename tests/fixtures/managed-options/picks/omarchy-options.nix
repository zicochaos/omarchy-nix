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
