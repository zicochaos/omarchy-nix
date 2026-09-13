# Manual probe (NOT wired into `nix flake check`): does the quickshell build
# under test survive a plugin reload with a working OSD?
#
# Context (docs/MAINTAINERS.md "Known broken", pkgs/quickshell.nix): on
# quickshell 0.3.0 the reload triggered by `omarchy plugin clone` left the
# OSD dead — the re-created IpcHandler was rejected ("another handler is
# registered for target osd") and the live registration belonged to the
# unloaded instance, so `omarchy osd` kept exiting 0 while nothing rendered
# until the shell restarted. The port pins 0.3.1, where the OSD survives the
# reload; `tests/ux.nix` (12) asserts that regression, and this probe is the
# standalone tool for re-testing any other build (e.g. before changing the
# pin, or after a quickshell release claims to fix the reload class).
#
# Sequence: baseline `omarchy osd` must render (probe sanity, both versions
# pass this) -> `omarchy plugin clone omarchy.clock` triggers the shell's
# full reload -> the OSD must still render.
#
# PASS = OSD survives the reload on this build. FAIL = OSD dead after the
# reload (finding reproduces).
#
# Run against the default (the repo's pin):
#   nix build --impure --no-link --print-out-paths --expr '
#     let f = builtins.getFlake "path:/path/to/omarchy-nix";
#         system = "x86_64-linux";
#         pkgs = import f.inputs.nixpkgs { inherit system; };
#     in pkgs.testers.nixosTest (import /path/to/omarchy-nix/tests/probe-quickshell-reload.nix {
#          inherit pkgs; lib = pkgs.lib; omarchy = f;
#          home-manager = f.inputs.home-manager; })'
# Swap the build under test by passing qsOverride, e.g.
#   qsOverride = p: p.quickshell.overrideAttrs (old: {
#     version = "0.3.2";
#     src = p.fetchFromGitea { domain = "git.outfoxxed.me"; owner = "quickshell";
#       repo = "quickshell"; tag = "v0.3.2"; hash = "sha256-..."; };
#   });
{
  pkgs,
  lib,
  omarchy,
  home-manager,
  # Build under test: null = the flake-injected pin (the repo's quickshell);
  # pass e.g. (p: p.quickshell.overrideAttrs ...) to probe another version.
  qsOverride ? null,
  ...
}:

{
  name = "qs-reload-probe";
  meta.maintainers = [ ];

  skipTypeCheck = true;

  nodes.machine =
    {
      config,
      pkgs,
      ...
    }:
    let
      omarchyCfg = {
        enable = true;
        managedPackagesFile = null;
        full_name = "Test User";
        email_address = "test@omarchy-nix.invalid";
      }
      # With no override the probe tests the flake-injected pin (the repo's
      # quickshell, i.e. omarchy.quickshellPackage's default). A plain
      # assignment beats the wrapper's mkDefault; overlaying pkgs.quickshell
      # would NOT work — the module consumes omarchy.quickshellPackage, not
      # the package set entry.
      // lib.optionalAttrs (qsOverride != null) {
        quickshellPackage = qsOverride pkgs;
      };
    in
    {
      imports = [
        omarchy.nixosModules.default
        home-manager.nixosModules.home-manager
      ];

      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      virtualisation.memorySize = 4096;
      virtualisation.cores = 4;

      omarchy = omarchyCfg;

      services.displayManager.sddm.enable = false;
      services.getty.autologinUser = "demo";
      programs.bash.loginShellInit = ''
        if [ "$(tty)" = "/dev/tty1" ]; then
          exec uwsm start -e -D Hyprland hyprland.desktop >/tmp/hyprland.log 2>&1
        fi
      '';

      users.users.demo = {
        isNormalUser = true;
        uid = 1000;
        password = "demo";
        extraGroups = [
          "wheel"
          "video"
          "input"
        ];
      };

      home-manager.users.demo = {
        imports = [ omarchy.homeManagerModules.default ];
        home.username = "demo";
        home.homeDirectory = "/home/demo";
        home.stateVersion = "26.05";
        omarchy.enable = true;
      };
    };

  testScript = ''
    import re

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_file("/run/user/1000/wayland-1", timeout=120)
    machine.wait_until_succeeds(
        "su - demo -c 'quickshell list 2>/dev/null | grep -q .'",
        timeout=60,
    )

    def as_demo(cmd):
        prefix = (
            "export XDG_RUNTIME_DIR=/run/user/1000; "
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
            "export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); "
        )
        return "su - demo -c '" + prefix + cmd + "'"

    machine.log(
        "quickshell binary: "
        + machine.succeed(
            "su - demo -c 'readlink -f $(command -v quickshell)'"
        ).strip()
        + " / "
        + machine.execute("su - demo -c 'quickshell --version 2>&1 || true'")[1].strip()
    )

    def shell_logs(tag):
        for f in ("log.qslog", "log.log"):
            out = machine.succeed(
                "tail -c 3000 /run/user/1000/quickshell/by-id/*/" + f + " 2>/dev/null || true"
            )
            machine.log("shell %s [%s]:\n%s" % (f, tag, out))

    def namespaces():
        layers_json = machine.succeed(as_demo("hyprctl -j layers"))
        return sorted(set(re.findall(r'"namespace"\s*:\s*"([^"]+)"', layers_json)))

    machine.log("layer namespaces at baseline: %s" % (namespaces(),))

    def osd_renders(label):
        # The ux test fires the OSD inside a retry loop (wait_until_succeeds);
        # a single shot can land before the OSD panel is ready, so retry here
        # too and log the raw IPC answers on failure.
        for attempt in range(6):
            status, out = machine.execute(
                as_demo("omarchy-osd -i volume-high -p 50 -d 4000")
            )
            machine.sleep(2)
            layers = machine.succeed(as_demo("hyprctl -j layers"))
            if "omarchy-osd" in layers:
                machine.log("OSD probe (%s): layer up on attempt %d" % (label, attempt + 1))
                return True
            if attempt == 0:
                machine.log(
                    "OSD probe (%s): attempt 1 exit=%d out=%r" % (label, status, out[:300])
                )
                state = machine.execute(as_demo("omarchy-shell -q osd state"))
                machine.log("osd state call: exit=%d out=%r" % (state[0], state[1][:200]))
        machine.log("OSD probe (%s): never rendered in 6 attempts" % label)
        return False

    # Sanity: the probe must find a working OSD before any reload, otherwise
    # a later failure would be meaningless.
    baseline = osd_renders("baseline")
    if not baseline:
        shell_logs("baseline failed")
        machine.log("layer namespaces now: %s" % (namespaces(),))
        machine.log(
            "quickshell processes: "
            + machine.succeed("pgrep -af quickshell | head -5 || true")
        )
    assert baseline, "probe invalid: OSD never rendered before any reload"
    machine.sleep(5)  # let it hide (4000 ms + animation)

    # Trigger the shell's plugin reload exactly like the documented flow.
    # `omarchy plugin clone` already polls until the shell discovers the new
    # plugin (it fails non-zero otherwise), so no extra wait is needed here —
    # and the as_demo wrapper is single-quoted, so no jq expression with
    # quotes can be embedded anyway.
    machine.succeed(as_demo("omarchy plugin clone omarchy.clock"))
    machine.sleep(2)  # let the reload settle

    _, warns = machine.execute(
        "journalctl -b --no-pager 2>/dev/null | grep -c 'another handler is registered' || true"
    )
    machine.log("'another handler is registered' warnings: %s" % warns.strip())

    # Strict: the FIRST OSD call after the reload must render. On 0.3.0 the
    # stale handler swallowed it in all 5 preserved runs, and in some runs it
    # keeps swallowing every call (the ux test's volume-OSD section timed out
    # after 30 s of retries in one such run), while a later call recovers in
    # others. Retrying here would hide exactly the state this probe exists to
    # detect, so this check does not retry.
    _, _ = machine.execute(as_demo("omarchy-osd -i volume-high -p 50 -d 4000"))
    machine.sleep(2)
    rendered = "omarchy-osd" in machine.succeed(as_demo("hyprctl -j layers"))
    machine.log("OSD probe (after reload, first call): layer=%s" % rendered)

    machine.screenshot("qs-reload-probe")
    assert rendered, (
        "OSD dead after plugin reload: the plugin-reload IPC finding "
        "reproduces on this quickshell build"
    )
    machine.log("PROBE RESULT: OSD survives the plugin reload on this build")
  '';
}
