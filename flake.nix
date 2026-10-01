{
  description = "NixOS port of basecamp/omarchy (Quattro generation)";

  inputs = {
    # Stable nixpkgs (26.05) so consumers on a stable NixOS install do NOT get
    # shifted to unstable by `nixos-rebuild switch --flake`. Hyprland >= 0.56
    # (the Quattro Lua config requirement — stable only has 0.55.4) comes from
    # the separate `hyprland` flake input below, which is self-contained (it
    # builds against its own nixpkgs, not this one).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Upstream Omarchy is NOT a flake; we vendor the quattro branch tree as a
    # derivation (see pkgs/omarchy.nix). Update with:
    #   nix flake lock --update-input omarchy-src
    omarchy-src = {
      url = "github:basecamp/omarchy/quattro";
      flake = false;
    };

    # Hyprland needs to be >= 0.56 for the Lua config Quattro uses. Pinned to
    # the v0.56.2 release upstream Omarchy ships (not the main branch), so
    # `nix flake update` cannot move the compositor to an untagged
    # snapshot. The rev is the release's "version: bump to 0.56.2" commit,
    # not the v0.56.2 tag: the tag commit (efb5099) only adds an automated
    # flake.lock bump to a nixpkgs with glaze 8, which the release's CMake
    # (`find_package(glaze 7...<8)`) rejects, so the tag's flake does not
    # build. Source is identical apart from flake.lock. Move back to a tag
    # once a release builds from its own lock.
    hyprland.url = "github:hyprwm/Hyprland/34170f65cc8dc4147613bbd25f8b89f4d8d2ed81";

    # Home-Manager pinned to the release branch matching stable nixpkgs
    # (26.05). Following the rolling master branch pulled a 26.11-pre HM
    # into a 26.05 system and tripped the state-version mismatch warning
    # on every evaluation.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # quickshell is NOT an input: this repo pins 0.3.1 in pkgs/quickshell.nix
    # (stable nixpkgs carries 0.3.0) and injects it as
    # omarchy.quickshellPackage. See that file for the measured reasons and
    # the drop condition.

    # Hermes Agent (Nous Research, MIT): the `hermes` default-agent CLI.
    # Upstream installs it with its own installer; here we consume the
    # project's own flake (uv2nix) instead of vendoring the packaging.
    # Fast-moving project — bump with `nix flake lock --update-input
    # hermes-agent` on the omarchy-src bump cadence. Its own nixpkgs
    # (unstable) stays deliberately un-followed: the package is built and
    # tested upstream against it. Its home-manager input only serves its own
    # checks (homeManagerModules eval), so it follows ours instead of
    # locking a second home-manager on master.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      omarchy-src,
      hyprland,
      home-manager,
      ...
    }:
    let
      # x86_64-only for now: the checks do not pass evaluation on aarch64
      # (hardware.graphics.enable32Bit is x86_64-only), so advertising the
      # arch was broken-by-declaration. Re-add when the checks evaluate
      # there (tracked on the dev tracker).
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # Read the upstream version file (e.g. "4.0.0.alpha"). It carries a
      # trailing newline — trim it once here so every consumer (package names,
      # derivation paths, meta) sees the clean value.
      omarchyVersion = nixpkgs.lib.strings.trim (builtins.readFile "${omarchy-src}/version");

      # External pkgs for packages/demo/tests. Global allowUnfree is
      # intentionally NOT set — it used to mask the real consumer path
      # (B0 allowUnfreePredicate) and let broken catalog unfreeNames slip
      # through. The default app set needs obsidian; the ux fixture enables
      # the steam feature while nixpkgs.pkgs isDefined (B0 skipped), so steam
      # + steam-unwrapped must live here too. claude-desktop and
      # zcode-desktop are named here only because they are unfree
      # derivations EXPOSED as packages outputs (nix flake check evaluates
      # every attr) — the consumer Install-menu path stays entry-scoped via
      # B0 from the catalog. Menu installs on the real consumer path (no
      # external pkgs) are covered by B0 from the catalog.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          # Explicit (docs/nix-best-practices.md): an --impure evaluation
          # would otherwise pick up ~/.config/nixpkgs/overlays.
          overlays = [ ];
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "obsidian"
              "steam"
              "steam-unwrapped"
              "claude-desktop"
              "zcode-desktop"
            ];
        };

      # Flake-owned derivations the Install-menu catalog addresses by attr
      # name when nixpkgs does not carry them (resolved by the module's
      # managed-packages block via omarchy.ownedPackages). The one
      # definition: the nixosModules wrapper injects it, and the catalog
      # checks are meant to consume it too. `packages` is this flake's
      # packages.<system> set (the wrapper passes its guarded hostPackages).
      ownedPackagesFor = system: packages: {
        inherit (packages) claude-desktop omp zcode-desktop;
        # Hermes Agent ships its own flake (uv2nix) — consume the packages
        # output directly instead of vendoring the build.
        hermes-agent = inputs.hermes-agent.packages.${system}.default;
      };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      # Vendoring derivation. The upstream tree lands at
      # $out/share/omarchy (the NixOS analogue of pacman's /usr/share/omarchy).
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          omarchy = pkgs.callPackage ./pkgs/omarchy.nix {
            inherit omarchy-src;
            version = omarchyVersion;
            # Path-adaptation deps for the 8 systemd user units (see pkgs/omarchy.nix).
            # bluez-tools provides bt-agent (not bluez); tailscale is only used
            # for ConditionPathExists / ExecStart path rewrite — the unit is
            # shipped but not enabled by the module.
            fcitx5 = pkgs.fcitx5;
            bluez-tools = pkgs.bluez-tools;
            pipewire = pkgs.pipewire;
            systemd = pkgs.systemd;
            tailscale = pkgs.tailscale;
          };
          # Plymouth boot-splash theme + SDDM login theme/Hyprland greeter.
          # Consumed by the omarchy NixOS module (boot.plymouth.themePackages
          # and services.displayManager.sddm theme wiring); also exposed for
          # standalone use.
          plymouth-omarchy-theme = pkgs.callPackage ./pkgs/plymouth-omarchy-theme.nix {
            inherit omarchy-src;
            version = omarchyVersion;
          };
          sddm-omarchy-theme = pkgs.callPackage ./pkgs/sddm-omarchy-theme.nix {
            inherit omarchy-src;
            version = omarchyVersion;
          };
          # Upstream-owned apps that are not in nixpkgs.
          # aether: theme generator (Wails). asdcontrol: Apple Studio Display
          # brightness. omacalc: calculator. omacut: video cutter (needs
          # ffmpeg on PATH at runtime).
          # omawrite: markdown writer. omasnap: screenshot capture + editor
          # (replaced tensaku upstream in 349ecc0).
          # monologue: webcam recorder (default app since 349ecc0).
          # hype: Markdown presentations (default app since 8b4eae6).
          # owe: wallpaper engine — video backgrounds + lock feed (349ecc0).
          # try: tobi's experiment-worktree CLI. hyprland-guiutils: hyprwm
          # dialog/run/welcome tools. hyprland-preview-share-picker: xdp
          # screencopy picker. omarchy-nvim: LazyVim starter + omarchy overlay.
          # claude-desktop: Anthropic's own Debian .deb unpacked + wrapped
          # (nixpkgs packaging pending in NixOS/nixpkgs#537215).
          # omp: Oh My Pi release binary (can1357/oh-my-pi, MIT).
          aether = pkgs.callPackage ./pkgs/aether.nix { };
          asdcontrol = pkgs.callPackage ./pkgs/asdcontrol.nix { };
          claude-desktop = pkgs.callPackage ./pkgs/claude-desktop.nix { };
          omp = pkgs.callPackage ./pkgs/omp.nix { };
          # zcode-desktop: Z.ai's ZCode, repackaged from the vendor's deb
          # (unfree; the menu icon font grows its U+E90F mark — see
          # pkgs/omarchy-icons/).
          zcode-desktop = pkgs.callPackage ./pkgs/zcode-desktop.nix { };
          omacalc = pkgs.callPackage ./pkgs/omacalc.nix { };
          omacut = pkgs.callPackage ./pkgs/omacut.nix { };
          omawrite = pkgs.callPackage ./pkgs/omawrite.nix { };
          monologue = pkgs.callPackage ./pkgs/monologue.nix { };
          hype = pkgs.callPackage ./pkgs/hype.nix { };
          owe = pkgs.callPackage ./pkgs/owe.nix { };
          omasnap = pkgs.callPackage ./pkgs/omasnap.nix { };
          try = pkgs.callPackage ./pkgs/try.nix { };
          hyprland-guiutils = pkgs.callPackage ./pkgs/hyprland-guiutils.nix { };
          hyprland-preview-share-picker = pkgs.callPackage ./pkgs/hyprland-preview-share-picker.nix { };
          omarchy-nvim = pkgs.callPackage ./pkgs/omarchy-nvim.nix { };
          omarchy-fish = pkgs.callPackage ./pkgs/omarchy-fish.nix { };
          # ttfx: screensaver engine (Rust TTE port; replaced
          # python-terminaltexteffects upstream in v4.0.0). herdr: terminal
          # workspace manager for coding agents (v4.0.0, ships alongside
          # tmux; not in nixpkgs).
          ttfx = pkgs.callPackage ./pkgs/ttfx.nix { };
          herdr = pkgs.callPackage ./pkgs/herdr.nix { };
          # quickshell 0.3.1 pin (stable nixpkgs carries 0.3.0). See the
          # file header for the measured reasons and the removal condition.
          quickshell = pkgs.callPackage ./pkgs/quickshell.nix { };
          # Icons for stock Omarchy themes (nixpkgs dropped yaru-theme with murrine).
          yaru-theme = pkgs.callPackage ./pkgs/yaru-theme.nix { };
          default = self.packages.${system}.omarchy;
        }
      );

      # NixOS module: enables Hyprland + quickshell + the omarchy runtime deps
      # and wires OMARCHY_PATH.
      #
      # This is the *flake wrapper*: it imports the pure module and injects the
      # flake-specific defaults. We also import upstream's
      # `hyprland.nixosModules.default`, which both pins Hyprland to the
      # `hyprland` input (>= 0.56 for the Lua config) and links `/share/hypr`
      # so Hyprland's Lua config provider can find the vendored config. The
      # pure module in modules/nixos/default.nix contains no flake references.
      nixosModules.default =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          imports = [
            inputs.hyprland.nixosModules.default
            ./modules/nixos/default.nix
          ];

          config =
            let
              # Package set for this host. Unsupported systems fail here with a
              # clear message instead of "attribute '…' missing" on self.packages.
              hostSystem = pkgs.stdenv.hostPlatform.system;
              hostPackages =
                self.packages.${hostSystem} or (throw "omarchy-nix supports x86_64-linux only (got ${hostSystem})");
            in
            lib.mkMerge [
              {
                # Inject the vendored omarchy derivation as the module default.
                # Consumers can override with omarchy.package = <derivation>.
                omarchy.package = lib.mkDefault hostPackages.omarchy;
                # Inject the system-theme packages (Plymouth + SDDM) so the pure
                # module can wire them without referencing the flake.
                omarchy.plymouthPackage = lib.mkDefault hostPackages.plymouth-omarchy-theme;
                omarchy.sddmPackage = lib.mkDefault hostPackages.sddm-omarchy-theme;

                # Inject the upstream-owned apps (not in nixpkgs, built under
                # pkgs/) so the pure module ships them without referencing the
                # flake. Consumers can drop entries with omarchy.exclude_packages
                # or override the whole list.
                omarchy.appPackages = lib.mkDefault (
                  with hostPackages;
                  [
                    aether
                    asdcontrol
                    omacalc
                    omacut
                    omawrite
                    monologue
                    hype
                    omasnap
                    owe
                    try
                    hyprland-guiutils
                    hyprland-preview-share-picker
                    omarchy-nvim
                    # Yaru-* icons: not pkgs.yaru-theme (throw-alias on new nixpkgs).
                    yaru-theme
                    # v4.0.0 upstream-owned binaries.
                    herdr
                    ttfx
                  ]
                );
                omarchy.nvimPackage = lib.mkDefault hostPackages.omarchy-nvim;

                # The desktop's quickshell build. Default is this flake's
                # 0.3.1 pin (see pkgs/quickshell.nix); a consumer can point it
                # at any other build with omarchy.quickshellPackage.
                omarchy.quickshellPackage = lib.mkDefault hostPackages.quickshell;

                # Flake-owned Install-menu derivations (see ownedPackagesFor
                # in the top-level let).
                omarchy.ownedPackages = lib.mkDefault (ownedPackagesFor hostSystem hostPackages);
                omarchy.fish.package = lib.mkDefault hostPackages.omarchy-fish;
              }

              # Mesa from the hyprland input's own nixpkgs, both halves. The
              # Hyprland flake's packages are built against that nixpkgs; a
              # system Mesa from another nixpkgs is the mismatch the Hyprland
              # wiki ("Installing Hyprland on NixOS", hyprwm/Hyprland#5148)
              # names as the cause of lag and FPS drops in GPU apps, and its
              # fix sets package and package32 from that same nixpkgs. The
              # version can be older or newer than this flake's stable pin;
              # matching Hyprland is the point, not freshness. package32
              # follows so 32-bit clients (Steam, Wine) load the same driver
              # build as 64-bit ones instead of a mixed pair.
              # mkOverride 500 wins over nixpkgs' mkDefault (1000) but a
              # consumer's plain = (100) still overrides each half.
              # Guarded by omarchy.enable: merely IMPORTING the module
              # must not change the host's Mesa.
              (lib.mkIf config.omarchy.enable (
                let
                  hyprlandPkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
                in
                {
                  hardware.graphics.package = lib.mkOverride 500 hyprlandPkgs.mesa;
                  hardware.graphics.package32 = lib.mkOverride 500 hyprlandPkgs.pkgsi686Linux.mesa;
                }
              ))
            ];
        };

      # Home-Manager module: seeds the Hyprland Lua entry point and the user
      # omarchy config (~/.config/omarchy, ~/.config/hypr).
      #
      # Under NixOS the module takes package/nvimPackage (and the other
      # values it reads) from osConfig.omarchy, which nixosModules.default
      # fills in. Standalone Home Manager has no system configuration to
      # read, so this wrapper injects the flake's derivations there, the
      # counterpart of nixosModules.default's injection; without them
      # `omarchy.enable = true` would have nothing to seed.
      homeModules.default =
        {
          lib,
          pkgs,
          osConfig ? null,
          ...
        }:
        {
          imports = [ ./modules/home-manager/default.nix ];

          config = lib.mkIf (!(osConfig ? omarchy)) (
            let
              hostSystem = pkgs.stdenv.hostPlatform.system;
              hostPackages =
                self.packages.${hostSystem} or (throw "omarchy-nix supports x86_64-linux only (got ${hostSystem})");
            in
            {
              omarchy.package = lib.mkDefault hostPackages.omarchy;
              omarchy.nvimPackage = lib.mkDefault hostPackages.omarchy-nvim;
            }
          );
        };
      # The output's former name, kept for existing consumers (`nix flake
      # check` reports it as an unknown output; homeModules is the standard
      # name).
      homeManagerModules.default = self.homeModules.default;

      # NixOS test harness (Stage 5): boots a VM with virtio-gpu-pci and
      # asserts the full desktop stack comes up — Hyprland + quickshell bar +
      # launcher. Runs automatically under `nix flake check` and protects the
      # port against regressions (new upstream rev, dep changes, refactors).
      #
      # The checks live in tests/checks/ (one file per check, wired by
      # tests/checks/default.nix). loadTest in tests/checks/lib.nix hands
      # the VM tests (tests/desktop.nix etc.) `self` and the home-manager
      # input, since testers.nixosTest can only pass `pkgs`.
      checks = forAllSystems (
        system:
        import ./tests/checks {
          inherit
            self
            inputs
            nixpkgs
            system
            ;
          pkgs = pkgsFor system;
          # The same set the nixosModules wrapper injects as
          # omarchy.ownedPackages, so the checks cannot drift from it.
          ownedPackages = ownedPackagesFor system self.packages.${system};
        }
      );

      nixosConfigurations = {
        # Minimal NixOS config that consumes the omarchy NixOS + Home-Manager
        # modules with `enable = true`. Used as the Stage 3/4 verification
        # vehicle (build the toplevel / a VM) and as a reference for consumers.
        # Not a substitute for example/configuration.nix, which Stage 5 wires
        # into a full desktop build.
        demo =
          let
            pkgs = pkgsFor "x86_64-linux";
          in
          nixpkgs.lib.nixosSystem {
            inherit pkgs;
            modules = [
              self.nixosModules.default
              inputs.home-manager.nixosModules.home-manager
              {
                omarchy.enable = true;
                omarchy.managedPackagesFile = null; # hermetic check (host /etc must not leak in)
                omarchy.full_name = "Omarchy Demo";
                omarchy.email_address = "demo@omarchy-nix.invalid";

                # Minimal VM-friendly base so the config builds standalone. The
                # filesystem is the QEMU virtio disk; SDDM runs under its own
                # wayland greeter (omarchy leaves the default SDDM, so we need
                # wayland.enable rather than a full xserver).
                fileSystems."/".device = "/dev/disk/by-label/nixos";
                fileSystems."/".fsType = "ext4";
                boot.loader.systemd-boot.enable = true;
                boot.loader.efi.canTouchEfiVariables = true;
                services.openssh.enable = true;
                services.displayManager.sddm.wayland.enable = true;
                users.users.demo = {
                  isNormalUser = true;
                  extraGroups = [
                    "wheel"
                    "video"
                    "input"
                  ];
                  initialPassword = "demo";
                };

                # Home-Manager seeds the per-user config (Hyprland Lua entry
                # point + user stubs + theme symlink). omarchy.enable is set
                # explicitly in HM (the module reads omarchy.* values from
                # osConfig.omarchy with a fallback to HM-local options, but does
                # not mirror enable itself to avoid an evaluation cycle).
                home-manager.users.demo = {
                  imports = [ self.homeModules.default ];
                  home.username = "demo";
                  home.homeDirectory = "/home/demo";
                  home.stateVersion = "26.05";
                  omarchy.enable = true;
                };

                virtualisation.vmVariant = {
                  virtualisation.memorySize = 4096;
                  virtualisation.cores = 8;
                };
                system.stateVersion = "26.05";
              }
            ];
          };

        # Reference consumer config (example/configuration.nix) wired exactly the
        # way README + docs/install.md show. Deliberately uses nixosSystem's OWN
        # nixpkgs instance (no pkgsFor / allowUnfree): `nix flake check`
        # evaluates it like an external consumer on a default nixpkgs config, so
        # a consumer-side eval break (e.g. an unfree default app) fails here
        # instead of at the user's first build.
        example = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./example/configuration.nix
            self.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [ self.homeModules.default ];
            }
          ];
        };
      }
      # Optional extra nixosConfigurations, spliced in only when the file
      # exists.
      // nixpkgs.lib.optionalAttrs (builtins.pathExists ./hosts/dev-configurations.nix) (
        import ./hosts/dev-configurations.nix {
          inherit
            inputs
            self
            nixpkgs
            pkgsFor
            ;
        }
      );
    };
}
