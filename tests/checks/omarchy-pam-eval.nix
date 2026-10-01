# Lock-screen PAM defaults: the password service must
# always be declared by the module, while the fingerprint service
# must stay absent unless the consumer opts in via
# omarchy.fingerprint.enable (the demo config in flake.nix does not).
# Opt-in presence is exercised at runtime by VM test section (4h).
{
  self,
  pkgs,
  ...
}:
let
  pamServices = self.nixosConfigurations.demo.config.security.pam.services;
in
if !(pamServices ? omarchy-lock-password) then
  throw "demo config is missing the omarchy-lock-password PAM service (must always be declared)"
else if (pamServices ? omarchy-lock-fingerprint) then
  throw "demo config has omarchy-lock-fingerprint without omarchy.fingerprint.enable"
else
  pkgs.runCommand "omarchy-pam-eval" { } "touch $out"
