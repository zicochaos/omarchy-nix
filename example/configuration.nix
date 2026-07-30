# Example consumer of omarchy-nix — the reference for public users.
#
# This file is a plain NixOS module: it sets omarchy.* options, creates the
# desktop user, and enables the omarchy Home-Manager module for them. The
# flake-side wiring (importing omarchy-nix's NixOS module + Home-Manager,
# and sharing the omarchy HM module with all users) lives in your flake.nix:
#
#   nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
#     system = "x86_64-linux";
#     modules = [
#       ./configuration.nix
#       omarchy-nix.nixosModules.default
#       home-manager.nixosModules.home-manager
#       { home-manager.sharedModules = [ omarchy-nix.homeManagerModules.default ]; }
#     ];
#   };
#
# In this repo the same wiring is exposed as the `example` flake output, so
# `nix flake check` evaluates this config exactly the way an external
# consumer's default nixpkgs would (in particular WITHOUT allowUnfree — the
# omarchy module whitelists the one unfree default app, obsidian, itself).
#
# Build and run as a VM (see docs/vm.md):
#
#   nix build .#nixosConfigurations.example.config.system.build.vm
#   QEMU_OPTS="-device virtio-gpu-pci" ./result/bin/run-nixos-vm
#
# The automated desktop test (checks.x86_64-linux.omarchy-desktop) exercises
# the same module stack headlessly — see tests/desktop.nix.
{ ... }:

{
  # One line enables the whole system layer: vendored omarchy on PATH,
  # OMARCHY_PATH session var, Quattro runtime deps, uwsm-managed Hyprland.
  omarchy.enable = true;

  # Menu-managed packages (Install/Remove menu). Wire this to the JSON inside
  # YOUR flake — pure flake evaluation cannot auto-detect absolute paths like
  # /etc/nixos/omarchy-packages.json. The guard keeps eval working before the
  # first menu install (file does not exist yet):
  omarchy.managedPackagesFile =
    if builtins.pathExists ./omarchy-packages.json then ./omarchy-packages.json else null;

  # Personal settings (all have sensible defaults; override what you need).
  omarchy.full_name = "Omarchy User";
  omarchy.email_address = "omarchy@example.com";
  omarchy.theme = "ethereal"; # one of the 22 stock themes
  omarchy.terminal = "foot";
  omarchy.scale = 1; # 1 for 1x displays, 2 for 2x (HiDPI)

  # The user that will run the desktop. Home-Manager seeds their config.
  users.users.omarchy = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "video"
      "input"
      "networkmanager"
      "ydotool" # voxtype dictation types via ydotoold (group-owned socket)
    ];
    # Console/SDDM login only: the module forces keys-only SSH by default,
    # so this documented password is not SSH-able. On real hardware use
    # initialHashedPassword instead (see docs/install.md).
    initialPassword = "omarchy";
  };

  # Home-Manager for the desktop user: seeds ~/.config/hypr/hyprland.lua
  # (the entry point dispatching into $OMARCHY_PATH), the user-editable
  # stubs, and the theme symlink. The omarchy HM module itself is already
  # shared with all users via home-manager.sharedModules (flake.nix wiring
  # above), so this block only carries the per-user settings.
  home-manager.users.omarchy = {
    home.username = "omarchy";
    home.homeDirectory = "/home/omarchy";
    home.stateVersion = "26.05";
    omarchy.enable = true;
  };

  # Minimal VM-friendly base so this config builds standalone for testing. A
  # real machine would have its own hardware/boot config instead of this
  # block. SDDM runs under its own wayland greeter (omarchy leaves the
  # default SDDM, so we need wayland.enable rather than a full xserver).
  fileSystems."/".device = "/dev/disk/by-label/nixos";
  fileSystems."/".fsType = "ext4";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  services.displayManager.sddm.wayland.enable = true;
  # sshd is on via the module already (mkDefault) with keys-only logins;
  # restated here for explicitness. Add openssh.authorizedKeys to the user
  # above for remote access, or opt into password auth explicitly with
  # services.openssh.settings.PasswordAuthentication = true.
  services.openssh.enable = true;

  virtualisation.vmVariant = {
    virtualisation.memorySize = 4096;
    virtualisation.cores = 8;
  };

  system.stateVersion = "26.05";
}
