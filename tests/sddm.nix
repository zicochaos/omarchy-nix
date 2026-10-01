# NixOS test: SDDM -> session acceptance (checks.omarchy-sddm).
#
# The other VM tests (desktop.nix, ux.nix, fish.nix) all disable SDDM and
# start the session from tty1, so nothing in CI covered the display-manager
# path: the SDDM daemon, the selected session handoff (display-manager ->
# uwsm), the omarchy theme selection, and the greeter's QML rendering the
# vendored theme. A regression there (theme renamed, session file not
# registered, theme QML broken) used to be invisible until a real install.
#
# Scope of the greeter wiring: the generated config is asserted statically
# (theme name, CompositorCommand + vendored hyprland.lua path) — autologin
# never launches the greeter compositor, and the test-mode greeter below
# runs on the user session's compositor, so `hyprland.lua` itself is not
# executed here. What IS executed is the greeter binary loading the vendored
# theme's QML.
#
# Autologin is used instead of driving the greeter: typing into a headless
# Wayland greeter is the flakiness the other tests deliberately avoid (see
# tests/desktop.nix).
{
  pkgs,
  lib,
  omarchy,
  home-manager,
  ...
}:

{
  name = "omarchy-sddm";
  meta.maintainers = [ ];

  nodes.machine =
    {
      config,
      ...
    }:
    {
      imports = [
        omarchy.nixosModules.default
        home-manager.nixosModules.home-manager
      ];

      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      virtualisation.memorySize = 4096;
      virtualisation.cores = 4;

      omarchy.enable = true;
      omarchy.managedPackagesFile = null; # hermetic check (host /etc must not leak in)
      omarchy.full_name = "Test User";
      omarchy.email_address = "test@omarchy-nix.invalid";

      # The path under test: SDDM launches the uwsm-managed Hyprland session.
      # autologin.user also makes the module set defaultSession =
      # "hyprland-uwsm" (the greeter can pick any other registered session).
      omarchy.autologin.user = "demo";

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
        imports = [ omarchy.homeModules.default ];
        home.username = "demo";
        home.homeDirectory = "/home/demo";
        home.stateVersion = "26.05";
        omarchy.enable = true;
      };
    };

  testScript = ''
    machine.start()

    # SDDM (the module's default display manager, mkDefault) is up. This is
    # the daemon the greeter and the session handoff both attach to.
    machine.wait_for_unit("display-manager.service")
    machine.succeed("systemctl is-active display-manager.service")

    # Autologin lands in the omarchy session without greeter interaction:
    # the Hyprland Wayland socket exists iff the session file SDDM launched
    # (hyprland-uwsm.desktop -> uwsm start -e -D Hyprland hyprland.desktop)
    # got through the Lua config chain.
    machine.wait_for_file("/run/user/1000/wayland-1", timeout=180)

    # quickshell registered its IPC instance — the desktop is really up
    # (same signal the other tests use).
    machine.wait_until_succeeds(
        "su - demo -c 'quickshell list 2>/dev/null | grep -q .'",
        timeout=60,
    )

    def as_demo(cmd):
        # Same session-env reconstruction as tests/ux.nix; `su -` resets the
        # environment, so XDG_RUNTIME_DIR / the session bus / the Hyprland
        # signature are re-exported. The wrapper groups cmd in single quotes,
        # so cmd may use double quotes but not single quotes.
        prefix = (
            "export XDG_RUNTIME_DIR=/run/user/1000; "
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
            "export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); "
        )
        return "su - demo -c '" + prefix + cmd + "'"

    # --- Session identity: the SDDM session file won, not a tty fallback. --
    # XDG_SESSION_DESKTOP=Hyprland is the desktop-name parity the custom
    # hyprland-uwsm.desktop exists to provide; XDG_SESSION_TYPE=wayland
    # proves the display manager launched a Wayland session.
    env = machine.succeed(as_demo("systemctl --user show-environment"))
    assert "XDG_SESSION_DESKTOP=Hyprland" in env.splitlines(), \
        "XDG_SESSION_DESKTOP=Hyprland missing from the SDDM session env"
    assert "XDG_SESSION_TYPE=wayland" in env.splitlines(), \
        "XDG_SESSION_TYPE=wayland missing from the SDDM session env"

    # logind agrees the display manager started the session: demo has a
    # graphical session (>= 1 tolerates the greeter's own session entry
    # before autologin takes over).
    sessions = machine.succeed("loginctl list-sessions --no-legend").strip().splitlines()
    demo_sessions = [s for s in sessions if "demo" in s]
    assert len(demo_sessions) >= 1, "no logind session for demo: %r" % sessions

    # --- Greeter wiring (static surface). --------------------------------
    # The generated SDDM config is what the daemon reads on a real install.
    conf = machine.succeed("cat /etc/sddm.conf.d/00-nixos.conf")
    assert "Current=omarchy" in conf, \
        "SDDM is not configured for the omarchy theme: %r" % conf
    # The exact session file block (G) wires: both hyprland-uwsm.desktop and
    # the bare hyprland.desktop set DesktopNames=Hyprland, so the runtime
    # env assert below cannot tell them apart — pin the configured name here.
    assert "Session=hyprland-uwsm.desktop" in conf, \
        "SDDM's autologin session is not the uwsm entry: %r" % conf
    assert "DefaultSession=hyprland-uwsm.desktop" in conf, \
        "SDDM's default session is not the uwsm entry: %r" % conf
    assert "CompositorCommand=Hyprland --config " in conf, \
        "SDDM's Wayland greeter does not run under Hyprland: %r" % conf
    assert "/share/sddm/hyprland.lua" in conf, \
        "CompositorCommand does not use the vendored greeter config: %r" % conf

    theme_dir = "/run/current-system/sw/share/sddm/themes/omarchy"
    for f in ("Main.qml", "theme.conf", "metadata.desktop", "logo.png"):
        machine.succeed("test -f %s/%s" % (theme_dir, f))

    # --- Greeter rendering of the vendored theme (autologin skips it). ----
    # Run SDDM's own greeter binary in test mode, on the running session,
    # against the vendored theme. Resolve the greeter through the `sddm` on
    # PATH (the display-manager module puts the package in systemPackages;
    # the unit itself execs a generated script) so this follows the package
    # the daemon actually runs.
    #
    # Where the evidence is: the greeter logs through SDDM's own message
    # handler into the journal; its stderr only carries libEGL noise. A
    # theme whose QML fails to load does NOT exit: SDDM logs the QML error,
    # then "Fallback to embedded theme", and keeps running with its built-in
    # theme, window mapped (measured with a theme importing a missing
    # module). Liveness alone therefore proves nothing; the journal must
    # show our Main.qml loading and no QML error or fallback.
    sddm_bin = machine.succeed("readlink -f $(command -v sddm)").strip()
    assert sddm_bin.endswith("/bin/sddm"), "unexpected sddm binary: %r" % sddm_bin
    greeter = sddm_bin[: -len("/bin/sddm")] + "/bin/sddm-greeter-qt6"
    machine.succeed("test -x " + greeter)

    with machine.nested("greeter loads the vendored theme and stays up"):
        machine.succeed(
            as_demo(
                "export WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland; "
                + greeter + " --test-mode --theme " + theme_dir
                + " > /tmp/greeter.log 2>&1 & echo $! > /tmp/greeter.pid"
            )
        )
        pid = machine.succeed("cat /tmp/greeter.pid").strip()
        greeter_journal = "journalctl -b --no-pager -o cat _PID=" + pid

        def greeter_failure(reason):
            machine.screenshot("greeter-failed")
            return AssertionError(
                "sddm-greeter %s; journal: %r; stderr: %r" % (
                    reason,
                    machine.execute(greeter_journal)[1],
                    machine.execute("cat /tmp/greeter.log")[1],
                )
            )

        # Positive readiness: the greeter created its view for the output
        # (logged after the theme QML was loaded or rejected) and its window
        # is mapped on the session's compositor.
        try:
            machine.wait_until_succeeds(
                greeter_journal + " | grep -q 'Adding view for'", timeout=60
            )
            machine.wait_until_succeeds(
                as_demo(
                    "hyprctl -j clients | jq -e \"any(.[]; .pid == "
                    + pid + " and .mapped)\""
                ),
                timeout=30,
            )
        except Exception:
            raise greeter_failure("never mapped a view")
        if machine.execute("kill -0 " + pid)[0] != 0:
            raise greeter_failure("exited after mapping its view")

        journal = machine.succeed(greeter_journal).splitlines()
        loading = "Loading file://" + theme_dir + "/Main.qml"
        if not any(line.startswith(loading) for line in journal):
            raise greeter_failure("did not load the vendored Main.qml")
        error_markers = [
            "Fallback to embedded theme",
            "is not installed",
            "is not a type",
            "QQmlApplicationEngine failed",
            "Failed to load",
            "ReferenceError",
            "TypeError",
            "Cannot assign to non-existent property",
            # any QML diagnostic located in the theme's own files
            "file://" + theme_dir + "/",
        ]
        problems = [
            line
            for line in journal
            if not line.startswith(loading) and any(m in line for m in error_markers)
        ]
        if problems:
            raise greeter_failure("logged QML problems %r" % problems)
        machine.succeed("kill " + pid)

    # Diagnostics for manual inspection (framebuffer painting under plain
    # QEMU is limited — see tests/desktop.nix; the assertions above are the
    # source of truth).
    machine.screenshot("sddm-session")
  '';
}
