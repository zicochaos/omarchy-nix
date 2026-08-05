# NixOS test: Omarchy (Quattro) UX / acceptance smoke test.
#
# Where tests/desktop.nix asserts the *processes* come up (Hyprland + the
# quickshell bar), this test exercises *real user behavior* end to end:
#   - a real Super+Enter keypress opens a foot terminal (the full dispatcher
#     chain: Hyprland bind -> Lua dispatcher -> omarchy-launch-terminal ->
#     xdg-terminal-exec -> foot), verified via hyprctl clients;
#   - the session env the module ships (XDG_SESSION_DESKTOP, BROWSER,
#     TERMINAL, OMARCHY_PATH) is actually in the user activation environment;
#   - the default-browser / cursor / first-run / systemd-user-unit wiring the
#     module + HM layer set up is present and observable.
#
# Session launch: unlike tests/desktop.nix (which execs bare `Hyprland` from
# tty1), this node execs the real uwsm session entry
#   `uwsm start -e -D Hyprland hyprland.desktop`
# from tty1. That is the faithful analogue of the module's
# hyprland-uwsm.desktop (what SDDM runs on a real install): it sets
# XDG_SESSION_DESKTOP=Hyprland and activates graphical-session.target (so the
# omarchy-* systemd user units start). tty1 autologin is kept because driving
# a Wayland display-manager greeter headlessly is flaky (see tests/desktop.nix);
# uwsm itself needs no greeter.
#
# Key injection: machine.send_key("meta_l-ret") reaches the guest as a real
# evdev keypress via QEMU's sendkey (QKeyCode meta_l = left Super, ret = Enter).
# That is the kernel-level path, the same one ydotool/uinput takes on real
# hardware and the ONLY path that reaches Hyprland's binding layer (Wayland
# virtual-keyboard protocols like wtype do not). On the nixos-omarchy Incus VM
# QMP sendkey is unavailable (incusd holds the monitor socket); the NixOS test
# driver owns QMP, so send_key works here.
{
  pkgs,
  lib,
  omarchy,
  home-manager,
  ...
}:

{
  name = "omarchy-ux";
  meta.maintainers = [ ];

  # testScriptWithTypes chokes on dynamic dispatch (same as tests/desktop.nix).
  skipTypeCheck = true;

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
      omarchy.full_name = "Test User";
      omarchy.email_address = "test@omarchy-nix.invalid";
      # Opt the test node into fingerprint lock auth so (4h) can assert the
      # omarchy-lock-fingerprint service exists; default-off is covered by the
      # eval-time omarchy-pam-eval check on the demo config.
      omarchy.fingerprint.enable = true;

      # The NixOS test instrumentation force-disables timesyncd (deterministic
      # guest clock); real NixOS defaults it on. Re-enable so the (4i) live
      # run of omarchy-update-time exercises the menu update.time path.
      services.timesyncd.enable = lib.mkForce true;

      environment.systemPackages = [
        pkgs.pamtester
        # (10) behavioral contract: tesseract+grim for the rendered-notification
        # OCR assertion, imagemagick for the deterministic OCR preprocessing
        # (raw full-screen OCR cannot read the bold notification title).
        # pactl is NOT listed here — volume media-key scripts require it from
        # omarchy runtimeDeps (issue #1 regression guard).
        pkgs.tesseract
        pkgs.imagemagick
      ];

      # Menu-managed packages fixture: proves JSON -> systemPackages and the
      # unfree whitelist extension at eval time. On real systems this file is
      # written by omarchy-nix-add/remove (Task 2 scripts).
      #
      # builtins.toFile creates a store path at eval time so the module can
      # read the JSON; the environment.etc entry mirrors it at /etc/nixos/
      # for runtime tools (omarchy-pkg-present). A bare string path like
      # "/etc/nixos/..." would not be readable at eval time — environment.etc
      # creates the file at activation, not evaluation.
      environment.etc."nixos/omarchy-packages.json".text = builtins.toJSON {
        packages = [ "firefox" ];
        features = [
          "steam"
          "xpadneo"
        ];
      };
      # Stub flake.nix alongside the JSON fixture so omarchy-pkg-present's
      # resolve_json() (which gates on flake.nix + omarchy-packages.json being
      # co-located) finds the fixture and the JSON membership path is exercised
      # by the (4d) truth table, not just the binary-probe fallback.
      environment.etc."nixos/flake.nix".text = "# omarchy-ux test stub";
      omarchy.managedPackagesFile = builtins.toFile "omarchy-packages.json" (
        builtins.toJSON {
          packages = [ "firefox" ];
          features = [
            "steam"
            "xpadneo"
          ];
        }
      );

      # (4i) the xpadneo feature entry must evaluate to the real
      # kernel-module option (managedFeatureDefs.xpadneo in the nixos module).
      assertions = [
        {
          assertion = config.hardware.xpadneo.enable;
          message = "xpadneo feature in omarchy-packages.json did not enable hardware.xpadneo";
        }
      ];

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

      # Test variant: tty1 autologin into the uwsm-managed Hyprland session
      # (the headless analogue of SDDM -> hyprland-uwsm.desktop on a real
      # install). SDDM stays disabled so the wayland.enable / xserver assertion
      # does not fire (see tests/desktop.nix).
      services.displayManager.sddm.enable = false;
      services.getty.autologinUser = "demo";
      programs.bash.loginShellInit = ''
        if [ "$(tty)" = "/dev/tty1" ]; then
          exec uwsm start -e -D Hyprland hyprland.desktop >/tmp/hyprland.log 2>&1
        fi
      '';
    };

  testScript = ''
    import json
    import re

    machine.start()

    # --- (1) Baseline: the compositor + shell are up. ----------------------
    machine.wait_for_unit("multi-user.target")

    # Hyprland's Wayland socket => the Lua config chain (bootstrap -> require
    # default.hypr.omarchy -> user stubs) loaded and the compositor initialized.
    machine.wait_for_file("/run/user/1000/wayland-1", timeout=120)

    # quickshell registered its instance (shell.qml loaded against the pinned
    # quickshell); same signal tests/desktop.nix relies on.
    machine.wait_until_succeeds(
        "su - demo -c 'quickshell list 2>/dev/null | grep -q .'",
        timeout=60,
    )

    def as_demo(cmd):
        # Run cmd as the demo user with the session env hyprctl and
        # `systemctl --user` need. `su -` resets the environment, so we
        # reconstruct XDG_RUNTIME_DIR, the session bus, and discover
        # HYPRLAND_INSTANCE_SIGNATURE from the runtime dir (uwsm/Hyprland
        # create /run/user/1000/hypr/<signature>). The wrapper groups cmd with
        # single quotes, so cmd may use double quotes but not single quotes.
        prefix = (
            "export XDG_RUNTIME_DIR=/run/user/1000; "
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
            "export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); "
        )
        return "su - demo -c '" + prefix + cmd + "'"

    # --- (1b) Session env: XDG_SESSION_DESKTOP=Hyprland. -------------------
    # uwsm -D Hyprland sets this; Hyprland's autostart.lua then runs
    # `systemctl --user import-environment $(env ...)` which pushes it into the
    # user activation environment. This is the desktop-name parity the custom
    # hyprland-uwsm.desktop exists to provide.
    def session_env():
        return machine.succeed(as_demo("systemctl --user show-environment"))

    env = session_env()
    assert "XDG_SESSION_DESKTOP=Hyprland" in env.splitlines(), \
        "XDG_SESSION_DESKTOP=Hyprland missing from session env"

    # --- (5) Session env: OMARCHY_PATH / BROWSER / TERMINAL. ---------------
    # Pushed into the activation env by the same autostart import. The values
    # come from environment.sessionVariables + uwsm env.d/10-omarchy; this
    # proves the session the user actually sees has the omarchy bin on PATH and
    # the omarchy launchers wired as BROWSER/TERMINAL.
    assert any(l.startswith("OMARCHY_PATH=") for l in env.splitlines()), \
        "OMARCHY_PATH missing from session env"
    assert "BROWSER=omarchy-launch-browser" in env.splitlines(), \
        "BROWSER=omarchy-launch-browser missing from session env"
    assert "TERMINAL=xdg-terminal-exec" in env.splitlines(), \
        "TERMINAL=xdg-terminal-exec missing from session env"

    # OMARCHY_USER_NAME/EMAIL arrive via the systemd user manager's own
    # environment.d processing — deliberately NOT via
    # environment.sessionVariables: NixOS renders those into PAM's
    # environment config, where a literal @ is a PAM item expansion — pam_env
    # logs "Expandable variables must be wrapped in {}" and drops the value.
    # (uwsm env.d alone is not sufficient either: the tty-autologin session
    # path does not deliver it into the manager env.) Pin both delivery
    # routes plus the absence of the PAM warning.
    #
    # Note: `systemctl show-environment` shell-escapes values containing
    # spaces ("Test User" prints as $'Test User'), so match on content.
    assert any(
        l.startswith("OMARCHY_USER_NAME=") and "Test User" in l
        for l in env.splitlines()
    ), "OMARCHY_USER_NAME missing from session env (environment.d route)"
    assert "OMARCHY_USER_EMAIL=test@omarchy-nix.invalid" in env.splitlines(), \
        "OMARCHY_USER_EMAIL missing from session env (environment.d route)"
    profile_email = machine.succeed("su - demo -c 'printf %s \"$OMARCHY_USER_EMAIL\"'")
    assert profile_email == "test@omarchy-nix.invalid", \
        "OMARCHY_USER_EMAIL missing from login-shell env (/etc/profile route): %r" % profile_email
    _st, pam_warnings = machine.execute(
        "journalctl -b --no-pager 2>/dev/null | grep -c 'Expandable variables' || true"
    )
    assert pam_warnings.strip() == "0", \
        "pam_env 'Expandable variables' warnings in journal: %s" % pam_warnings

    # --- (5b) Wired omarchy.* options: timezone + terminal list. -----------
    # omarchy.timezone -> time.timeZone (mkDefault; nothing else in this test
    # config sets it, so the module default Etc/UTC must win through).
    # omarchy.terminal -> /etc/xdg/hyprland-xdg-terminals.list, which
    # xdg-terminal-exec searches before the vendored data-dir fallback.
    tz = machine.succeed("timedatectl show -p Timezone --value").strip()
    assert tz == "Etc/UTC", \
        "omarchy.timezone not wired to time.timeZone: %r" % tz
    terms = machine.succeed("cat /etc/xdg/hyprland-xdg-terminals.list")
    assert "foot.desktop" in terms.split(), \
        "hyprland-xdg-terminals.list missing foot.desktop: %r" % terms

    # --- (3) Default browser = chromium. -----------------------------------
    # finalize-user (run from first-run on session start) does
    # `xdg-settings set default-web-browser chromium.desktop`; the HM activation
    # mirror is best-effort (`|| true`) and may not resolve chromium.desktop
    # during root-run system activation. So this races first-run: wait for
    # finalize-user to set the chromium.desktop alias (the name upstream + the
    # oracle use) rather than the nixpkgs chromium-browser.desktop default.
    def browser_is_chromium(_last):
        return machine.succeed(as_demo("xdg-settings get default-web-browser")).strip() == "chromium.desktop"

    with machine.nested("waiting for default-web-browser to become chromium.desktop"):
        retry(browser_is_chromium, timeout_seconds=120)

    # --- (4) Cursor mechanism (mechanism parity, not screenshot). ----------
    # Upstream sets no cursor theme name; libxcursor resolves the theme named
    # "default" via icons/default/index.theme -> Inherits=Adwaita. adwaita-icon-
    # theme provides the actual cursors. `grim` cannot capture the hardware
    # cursor plane, so presence is verified by the same files the upstream
    # reference install has, not by screenshot.
    machine.succeed("test -f /run/current-system/sw/share/icons/default/index.theme")
    machine.succeed("grep -q Inherits=Adwaita /run/current-system/sw/share/icons/default/index.theme")
    machine.succeed("test -s /run/current-system/sw/share/icons/Adwaita/cursors")

    # --- (4b) Webapp icons (launcher Apps view). ----------------------------
    # The vendored applications/*.desktop use bare icon names (Icon=chatgpt,
    # Icon=disk-usage, Icon=google-contacts). pkgs/omarchy.nix installs the
    # PNGs from applications/icons/ into share/icons/hicolor/256x256/apps/
    # lowercased + hyphenated (upstream /usr/share/icons parity, verified on
    # the Arch reference box). Without them the launcher shows blank tiles.
    for icon in ["chatgpt", "disk-usage", "google-contacts", "youtube", "x"]:
        machine.succeed(
            "test -f /run/current-system/sw/share/icons/hicolor/256x256/apps/"
            + icon + ".png"
        )

    # --- (4c) Dictation stack (voxtype + ydotool). --------------------------
    # voxtype is shipped declaratively (upstream parity: Install → AI →
    # Dictation); Arch voxtype-bin also installs Voxtype Configuration.desktop
    # so Super+Space → Apps can open the TUI — assert that entry is present.
    machine.succeed("test -f /run/current-system/sw/share/applications/voxtype-configure.desktop")
    # default/hypr/bindings/voxtype.lua binds F9 + Super+Ctrl+X
    # when the binary is on PATH. [output] mode = "type" needs ydotool, whose
    # daemon is enabled via programs.ydotool.
    machine.succeed("command -v voxtype")
    machine.succeed("command -v ydotool")
    machine.succeed("systemctl is-enabled --quiet ydotoold.service")

    # eval-side proof: the JSON fixture landed in the system profile
    machine.succeed("command -v firefox")
    machine.succeed("command -v steam")  # feature steam -> programs.steam.enable

    # --- (4d) omarchy-pkg-present truth table (B9 reactivated) --------------
    machine.succeed("omarchy-pkg-present firefox")        # packages entry in JSON fixture
    machine.succeed("omarchy-pkg-present steam")          # features entry in JSON fixture
    machine.succeed("omarchy-pkg-present foot")           # binary probe (runtimeDeps)
    machine.succeed("omarchy-pkg-present voxtype-bin")    # alias -> binary probe
    machine.fail("omarchy-pkg-present brave-bin")         # neither -> exit 1
    machine.fail("omarchy-pkg-present microsoft-edge-stable-bin")

    # --- (4e) omarchy-nix-add / omarchy-nix-remove (DRY-RUN, no rebuild) ----
    machine.succeed("mkdir -p /tmp/consumer-flake")
    machine.succeed("touch /tmp/consumer-flake/flake.nix")
    env = "OMARCHY_NIX_FLAKE=/tmp/consumer-flake OMARCHY_NIX_UPDATE_DRY_RUN=1 "
    machine.succeed(env + "omarchy-nix-add install.browser.firefox")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert '"firefox"' in out, out
    # idempotent: second add is a no-op and exits 0
    machine.succeed(env + "omarchy-nix-add install.browser.firefox")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert out.count("firefox") == 1, out
    # feature entry lands in features, not packages
    machine.succeed(env + "omarchy-nix-add install.gaming.steam")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert '"steam"' in out, out
    # unknown raw attribute: exit 1, JSON untouched
    machine.fail(env + "omarchy-nix-add definitely-not-a-real-attr-xyz")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert "definitely-not" not in out, out
    # remove by entry id (feature) and by raw attr
    machine.succeed(env + "omarchy-nix-remove install.gaming.steam")
    machine.succeed(env + "omarchy-nix-remove firefox")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert "steam" not in out and "firefox" not in out, out
    # git-based consumer flake: JSON is registered with intent-to-add so the
    # flake snapshot (which only sees tracked files) includes it at eval time
    machine.succeed("git -C /tmp/consumer-flake init -q")
    machine.succeed(env + "omarchy-nix-add install.browser.firefox")
    out = machine.succeed("git -C /tmp/consumer-flake ls-files")
    assert "omarchy-packages.json" in out, out
    # early-exit (already installed) retries the registration without failing
    machine.succeed(env + "omarchy-nix-add install.browser.firefox")
    out = machine.succeed("git -C /tmp/consumer-flake ls-files")
    assert "omarchy-packages.json" in out, out
    # batch: multiple ids in one call = one transaction, and every
    # operation leaves a durable audit log under the state dir
    machine.succeed(env + "omarchy-nix-add install.gaming.steam install.gaming.xbox-controllers")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert '"steam"' in out and '"xpadneo"' in out, out
    machine.succeed(env + "omarchy-nix-remove install.gaming.steam install.gaming.xbox-controllers")
    out = machine.succeed("cat /tmp/consumer-flake/omarchy-packages.json")
    assert "steam" not in out and "xpadneo" not in out, out
    machine.succeed("ls /root/.local/state/omarchy/nix-add/*.log")

    # --- (4f) zram swap + zswap off (upstream parity, B2) -------------------
    swaps = machine.succeed("cat /proc/swaps")
    assert "/dev/zram0" in swaps, swaps
    pri = machine.succeed("swapon --show=PRIO --noheadings /dev/zram0").strip()
    assert pri == "100", pri
    alg = machine.succeed("cat /sys/class/block/zram0/comp_algorithm")
    assert "[zstd]" in alg, alg
    zswap = machine.succeed("cat /sys/module/zswap/parameters/enabled").strip()
    assert zswap == "N", zswap

    # omarchy-nix-search: non-interactive filter mode over a fixture index
    machine.succeed("mkdir -p /tmp/idx")
    machine.succeed("printf 'firefox\\tWeb browser\\t153.0\\nhtop\\tProcess viewer\\t3.3.0\\n' > /tmp/idx/index.tsv")
    out = machine.succeed("OMARCHY_NIX_INDEX_FILE=/tmp/idx/index.tsv omarchy-nix-search --filter fire")
    assert "firefox" in out and "htop" not in out, out

    # omarchy-file-select: store-python shebang; an unknown option
    # exits 2 with the script's own message (proves interpreter + gi imports
    # work headless — the script sets add_help=False, so --help is
    # intentionally absent; before the fix this died with bad interpreter).
    out = machine.succeed("head -1 /run/current-system/sw/share/omarchy/bin/omarchy-file-select")
    assert "/nix/store" in out, out
    _rc, out = machine.execute("omarchy-file-select --definitely-unknown 2>&1")
    assert _rc == 2 and "unknown option" in out, out
    # model-usage scanners (bump follow-up): executable with store python
    machine.succeed(
        "/run/current-system/sw/share/omarchy/shell/plugins/model-usage/scripts/claude_usage_scanner.py --help >/dev/null"
    )

    # menu rewiring is live in the vendored tree
    menu = machine.succeed("cat /run/current-system/sw/share/omarchy/default/omarchy/omarchy-menu.jsonc")
    assert menu.count("omarchy-nix-add") >= 44, menu.count("omarchy-nix-add")
    assert menu.count("omarchy-nix-remove") >= 12, menu.count("omarchy-nix-remove")
    assert "omarchy-nix-search" in menu

    # --- (4g) migrations: classification, seeding, fail-closed -------------
    # Fake OMARCHY_PATH tree with fixture migrations + manifest + adapters,
    # driven via the OMARCHY_PATH / OMARCHY_MIGRATION_STATE env overrides.
    machine.succeed("mkdir -p /tmp/omig/migrations /tmp/omig/migrations-nix")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/a-ran' > /tmp/omig/migrations/1000000001.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/b-ran' > /tmp/omig/migrations/1000000002.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/d-VENDORED-ran' > /tmp/omig/migrations/1000000004.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/d-adapter-ran' > /tmp/omig/migrations-nix/1000000004.sh")
    machine.succeed(
        "jq -n '{\"1000000001.sh\":\"user-safe\",\"1000000002.sh\":\"skip\",\"1000000004.sh\":\"adapter\"}'"
        " > /tmp/omig/migrations-nix.json"
    )
    mig = "OMARCHY_PATH=/tmp/omig OMARCHY_MIGRATION_STATE=/tmp/omig-state omarchy-migrate"

    # fresh user: --pending is read-only and reports nothing (unseeded == baseline)
    machine.fail(mig + " --pending")
    # first run baselines everything without executing any script
    out = machine.succeed(mig)
    assert "baselining" in out, out
    machine.fail("test -e /tmp/omig/a-ran")
    machine.fail("test -e /tmp/omig/d-adapter-ran")
    machine.succeed("test -f /tmp/omig-state/1000000001.sh")
    machine.succeed("test -f /tmp/omig-state/1000000002.sh")
    machine.succeed("test -f /tmp/omig-state/1000000004.sh")
    machine.fail(mig + " --pending")

    # a "bump" adds new migrations in every class plus an unclassified one
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/e-ran' > /tmp/omig/migrations/1000000005.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/f-ran' > /tmp/omig/migrations/1000000006.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'exit 1' > /tmp/omig/migrations/1000000007.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/h-VENDORED-ran' > /tmp/omig/migrations/1000000008.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/h-adapter-ran' > /tmp/omig/migrations-nix/1000000008.sh")
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/i-ran' > /tmp/omig/migrations/1000000009.sh")
    machine.succeed(
        "jq '. + {\"1000000005.sh\":\"user-safe\",\"1000000006.sh\":\"skip\","
        "\"1000000007.sh\":\"user-safe\",\"1000000008.sh\":\"adapter\"}'"
        " /tmp/omig/migrations-nix.json > /tmp/omig/m.json && mv /tmp/omig/m.json /tmp/omig/migrations-nix.json"
    )
    out = machine.succeed(mig + " --pending")
    for n in ("1000000005", "1000000006", "1000000007", "1000000008", "1000000009"):
        assert n in out, out

    # dry-run reports but mutates nothing; it still exits 1 on structural
    # problems (the unclassified 1000000009) — fail-closed also in dry-run
    _rc, out = machine.execute("OMARCHY_NIX_UPDATE_DRY_RUN=1 " + mig + " 2>&1")
    assert _rc == 1, out
    assert "DRY-RUN" in out, out
    assert "not classified" in out, out
    machine.fail("test -e /tmp/omig/e-ran")
    machine.fail("test -f /tmp/omig-state/1000000005.sh")

    # real run: the failing user-safe + the unclassified one fail the run,
    # but the rest of the queue is still attempted
    machine.fail(mig)
    machine.succeed("test -e /tmp/omig/e-ran")                    # user-safe ran
    machine.succeed("test -f /tmp/omig-state/1000000005.sh")      #   ... and marked
    machine.fail("test -e /tmp/omig/f-ran")                       # skip did not run
    machine.succeed("test -f /tmp/omig-state/1000000006.sh")      #   ... but marked
    machine.fail("test -f /tmp/omig-state/1000000007.sh")         # failed: NOT marked
    machine.succeed("test -e /tmp/omig/h-adapter-ran")            # adapter ran
    machine.fail("test -e /tmp/omig/h-VENDORED-ran")              #   ... vendored did NOT
    machine.succeed("test -f /tmp/omig-state/1000000008.sh")
    machine.fail("test -e /tmp/omig/i-ran")                       # unclassified: refused
    machine.fail("test -f /tmp/omig-state/1000000009.sh")

    # fix both, rerun: the failed migration retries and succeeds
    machine.succeed("printf '%s\\n' '#!/bin/bash' 'touch /tmp/omig/g-ran' > /tmp/omig/migrations/1000000007.sh")
    machine.succeed(
        "jq '. + {\"1000000009.sh\":\"skip\"}' /tmp/omig/migrations-nix.json"
        " > /tmp/omig/m.json && mv /tmp/omig/m.json /tmp/omig/migrations-nix.json"
    )
    machine.succeed(mig)
    machine.succeed("test -e /tmp/omig/g-ran")
    machine.succeed("test -f /tmp/omig-state/1000000007.sh")
    machine.succeed("test -f /tmp/omig-state/1000000009.sh")
    machine.fail(mig + " --pending")

    # real tree: the packaged manifest classifies every vendored migration
    machine.succeed("ls /run/current-system/sw/share/omarchy/migrations/*.sh | xargs -n1 basename | sort > /tmp/omig/vendored.txt")
    machine.succeed("jq -r 'keys[]' /run/current-system/sw/share/omarchy/migrations-nix.json | sort > /tmp/omig/manifest.txt")
    out = machine.succeed("comm -23 /tmp/omig/vendored.txt /tmp/omig/manifest.txt")
    assert out.strip() == "", "unclassified vendored migrations: %s" % out
    out = machine.succeed("comm -13 /tmp/omig/vendored.txt /tmp/omig/manifest.txt")
    assert out.strip() == "", "stale manifest keys: %s" % out

    # --- (4h) lock-screen PAM -----------------------------------------------
    # omarchy-lock-password is always present; the fingerprint service is
    # present here because the test node opts in (omarchy.fingerprint.enable).
    machine.succeed("test -f /etc/pam.d/omarchy-lock-password")
    machine.succeed("grep -q pam_faillock /etc/pam.d/omarchy-lock-password")
    machine.succeed("grep -q pam_unix /etc/pam.d/omarchy-lock-password")
    machine.succeed("test -f /etc/pam.d/omarchy-lock-fingerprint")
    machine.succeed("grep -q pam_fprintd /etc/pam.d/omarchy-lock-fingerprint")
    # fprintd is dbus-activated; the unit exists once the option is on
    machine.succeed("systemctl cat fprintd.service >/dev/null")

    # wrong password rejected, correct password accepted (PAM level — the
    # Quickshell PamContext consumes these same service files)
    _rc, out = machine.execute("echo wrong-password | pamtester omarchy-lock-password demo authenticate 2>&1")
    assert _rc != 0, out
    _rc, out = machine.execute("echo demo | pamtester omarchy-lock-password demo authenticate 2>&1")
    assert _rc == 0, out

    # runtime PAM writers are declarative stubs and must not write /etc/pam.d
    out = machine.succeed("omarchy-setup-lock")
    assert "declarative" in out, out
    out = machine.succeed("omarchy-setup-security-fingerprint")
    assert "omarchy.fingerprint.enable" in out, out
    out = machine.succeed("omarchy-remove-security-fingerprint")
    assert "declarative" in out, out

    # --- (4i) runtime mutator quarantine -----------------------------------
    # Arch system mutators are neutralized: declarative-note stubs print a
    # NixOS note and exit 0 without touching system state.
    for script in [
        "omarchy-dns",
        "omarchy-sudo-passwordless",
        "omarchy-menu-timezone",
        "omarchy-hibernation-setup",
        "omarchy-install-service-sunshine",
        "omarchy-install-browser",
        "omarchy-refresh-limine",
        "omarchy-reinstall-configs",
        "omarchy-refresh-sddm",
    ]:
        out = machine.succeed(script)
        assert "NixOS:" in out, "%s did not print its stub note: %r" % (script, out)

    # nixos-adapted no-ops: browser policy writes are gone (silent, so
    # omarchy-theme-set output stays clean) and firmware update no longer
    # stages anything on the ESP.
    out = machine.succeed("omarchy-theme-set-browser")
    assert out.strip() == "", "theme-set-browser should be a silent no-op: %r" % out
    machine.succeed("test -x $(command -v omarchy-update-firmware) && ! grep -qF '/boot/EFI' $(command -v omarchy-update-firmware)")
    machine.succeed("test -x $(command -v omarchy-install-dev-env) && ! grep -qF '/etc/php' $(command -v omarchy-install-dev-env)")

    # user-safe with audited leftovers: timesyncd restart is transient and
    # works on NixOS (menu update.time stays live).
    machine.succeed("omarchy-update-time")

    # Arch-only mutators are hidden from the menu entirely.
    menu = machine.succeed(
        "cat /run/current-system/sw/share/omarchy/default/omarchy/omarchy-menu.jsonc"
    )
    for hid in [
        "setup.direct-boot",
        "setup.security.fido2",
        "setup.security.passwordless-sudo",
        "remove.security.fido2",
        "trigger.hardware.hybrid-gpu",
        "update.config.plymouth",
        "style.unlock",
        "update.timezone",
        "install.browser.zen",
        "install.browser.brave-origin",
        "remove.browser.zen",
        "remove.browser.brave-origin",
    ]:
        assert '"%s"' % hid not in menu, "menu still exposes %s" % hid

    # Xbox controllers route into the catalog feature: the menu action is
    # rewired to omarchy-nix-add and pkg-present resolves the Arch package
    # name through the features entry in the JSON fixture (xpadneo feature
    # -> hardware.xpadneo.enable, asserted at eval time above).
    machine.succeed(
        "grep -qF 'omarchy-nix-add install.gaming.xbox-controllers' "
        "/run/current-system/sw/share/omarchy/default/omarchy/omarchy-menu.jsonc"
    )
    machine.succeed("omarchy-pkg-present xpadneo-dkms")

    # omarchy-version reports the package version from the store path, not
    # the Arch package database (as_demo shells carry OMARCHY_PATH via PAM).
    out = machine.succeed(as_demo("omarchy-version")).strip()
    assert out not in ("dev", "") and "unknown" not in out, out

    # nixos-adapted sshd flows keep the user-state part (authorized_keys)
    # while the daemon/firewall stay declarative. gum confirm reads piped
    # stdin, so printf 'y' drives the removal prompt.
    machine.succeed(as_demo("mkdir -p ~/.ssh && ssh-keygen -q -t ed25519 -N \"\" -f ~/.ssh/id_ed25519_test"))
    pubkey = machine.succeed("cat /home/demo/.ssh/id_ed25519_test.pub").strip()
    machine.succeed(as_demo("omarchy-setup-security-sshd --key=\"%s\"" % pubkey))
    machine.succeed("grep -qF 'ssh-ed25519' /home/demo/.ssh/authorized_keys")
    machine.succeed(as_demo("printf \"y\\n\" | omarchy-remove-security-sshd"))
    _rc, _out = machine.execute("test -f /home/demo/.ssh/authorized_keys")
    assert _rc != 0, "authorized_keys still present after remove"

    # --- (2) Super+Enter opens a foot terminal. ----------------------------
    # Count foot windows via hyprctl before/after the keypress, so we assert a
    # *new* window appeared (not just that one exists). class==foot proves the
    # full chain landed on foot (the only entry in hyprland-xdg-terminals.list).
    def foot_classes():
        clients = json.loads(machine.succeed(as_demo("hyprctl clients -j")))
        return [c.get("class") for c in clients]

    before = foot_classes()
    assert "foot" not in before, "foot already open before keypress: %r" % before

    # meta_l = left Super, ret = Enter (QEMU QKeyCode names). This injects a
    # real kernel keypress chord; the NixOS test driver owns the QMP monitor so
    # sendkey reaches the guest, unlike the incusd-held monitor on real-VM tests.
    machine.send_key("meta_l-ret")

    def foot_open(_last_try):
        return "foot" in foot_classes()

    with machine.nested("waiting for Super+Enter to open foot"):
        retry(foot_open, timeout_seconds=30)

    foot_windows = [c for c in foot_classes() if c == "foot"]
    assert foot_windows, "no foot window after Super+Enter"
    assert all(c == "foot" for c in foot_windows), \
        "unexpected terminal class: %r" % foot_windows

    # --- (6) Systemd user units. -------------------------------------------
    # The omarchy-* units are tied to graphical-session.target (uwsm activates
    # it). omarchy-sleep-lock must be active; omarchy-fcitx5 must at least be
    # loaded (it may fail to fully run without real input hardware, but the unit
    # ships and starts with the session).
    machine.wait_until_succeeds(
        as_demo("systemctl --user is-active --quiet omarchy-sleep-lock.service"),
        timeout=60,
    )
    fcitx_load = machine.succeed(
        as_demo("systemctl --user show -p LoadState --value omarchy-fcitx5.service")
    ).strip()
    assert fcitx_load == "loaded", \
        "omarchy-fcitx5 LoadState is %r, expected loaded" % fcitx_load

    # wayland.conf stub (port-side seed): allowOverrideXKB must be False so
    # fcitx5's selfDiagnose does not notify "Sending keyboard layout
    # configuration ... not yet supported on current desktop" 10s into every
    # session — the override only works on KDE/GNOME, never on Hyprland.
    machine.succeed(
        "grep -q '^Allow Overriding System XKB Settings=False' "
        "/home/demo/.config/fcitx5/conf/wayland.conf"
    )

    # --- (6b) Upstream base-list parity (gaps closed 2026-07-28): screen
    # recording (bar indicator + omarchy-capture-screenrecording), print
    # applet (nixpkgs names the binary system-config-printer-applet; the
    # vendored Hidden=true stub masks its autostart exactly like upstream).
    machine.succeed("command -v gpu-screen-recorder")
    machine.succeed("command -v system-config-printer-applet")
    # The KMS backend needs the setcap wrapper, not just the package on PATH
    # ("pkexec must be setuid root" otherwise — verified on real hardware).
    gsr_cap = machine.succeed("getcap /run/wrappers/bin/gsr-kms-server").strip()
    assert "cap_sys_admin" in gsr_cap, \
        "gsr-kms-server wrapper missing cap_sys_admin: %r" % gsr_cap
    # UPower: the shell's battery service + power panel read UPower over
    # DBus; without the daemon every battery read silently says "not
    # present" (the VM has no battery, but the daemon must run).
    machine.wait_until_succeeds("systemctl is-active --quiet upower", timeout=30)
    # Kvantum is gone: upstream dropped kvantum/kvantum-qt5 from
    # omarchy-base.packages (migrations/1785351479.sh pacman-removes them on
    # Arch; envs.lua no longer sets QT_STYLE_OVERRIDE), so the port must not
    # ship the QStyle plugin in the system profile either.
    kvantum = machine.succeed(
        # -L: buildEnv symlinks single-provider leaf dirs (plugins/styles
        # here), and find without -L will not descend into them.
        "find -L /run/current-system/sw/lib -name 'libkvantum.so' -print -quit"
    ).strip()
    assert "libkvantum" not in kvantum, \
        "kvantum QStyle plugin still in the system profile: %r" % kvantum

    # The running compositor must report zero config errors. Hyprland
    # >= 2b1723adda forwards descriptor details (min/max ranges) to Lua-set
    # values, so an out-of-range vendored value now fails loudly instead of
    # passing silently (real case: group.groupbar.indicator_height = 0,
    # descriptor min 1 — shipped by upstream, only valid on older Hyprland).
    # Assert the class here, on the live session, so the next range-tightening
    # commit cannot slip through green VM runs again.
    cfgerr = machine.succeed(as_demo("hyprctl configerrors")).strip()
    assert cfgerr == "", "Hyprland config errors on the running session: %r" % cfgerr

    # --- (7) First-run evidence. -------------------------------------------
    # autostart.lua runs omarchy-first-run on hyprland.start; it calls
    # omarchy-finalize-user (which writes ~/.XCompose via install/user/all.sh ->
    # xcompose.sh) then logs each step and marks done/first-run-user on success.
    machine.wait_until_succeeds(
        "test -f /home/demo/.local/state/omarchy/done/first-run-user",
        timeout=180,
    )
    machine.succeed("test -f /home/demo/.local/state/omarchy/first-run.log")
    machine.succeed("grep -q 'Completed: set GNOME theme' /home/demo/.local/state/omarchy/first-run.log")
    machine.succeed("grep -q 'Completed: show welcome notification' /home/demo/.local/state/omarchy/first-run.log")
    machine.succeed("test -f /home/demo/.XCompose")

    # --- (7b) NixOS agent skill + update-safe managed links. ---------------
    # Upstream finalize-user links each agent to $OMARCHY_PATH once. Because
    # that is a generation-specific store path on NixOS, Home Manager must
    # adopt and refresh the links on every activation. Simulate an old
    # generation by redirecting all four links to a stale directory, delete
    # that directory (as GC would), rerun the HM activation unit, and require
    # the links to point at the active package target again.
    with machine.nested("NixOS agent skill links survive package updates"):
        skill_paths = [
            ".agents/skills/omarchy",
            ".claude/skills/omarchy",
            ".codex/skills/omarchy",
            ".pi/agent/skills/omarchy",
        ]
        expected = machine.succeed(
            as_demo("readlink -f \"$OMARCHY_PATH/default/omarchy-skill\"")
        ).strip()
        assert expected.startswith("/nix/store/"), expected

        for skill_path in skill_paths:
            resolved = machine.succeed(
                as_demo("readlink -f ~/" + skill_path)
            ).strip()
            assert resolved == expected, \
                "%s resolves to %r, expected %r" % (skill_path, resolved, expected)
            machine.succeed(
                as_demo("grep -Fq \"Omarchy on NixOS\" ~/" + skill_path + "/SKILL.md")
            )

        machine.succeed("mkdir -p /tmp/stale-omarchy-skill")
        for skill_path in skill_paths:
            machine.succeed(
                "ln -sfn /tmp/stale-omarchy-skill /home/demo/" + skill_path
            )

        # Simulate garbage collection of the old generation: the stale target
        # disappears, leaving all four links dangling (test -e follows symlinks).
        machine.succeed("rm -rf /tmp/stale-omarchy-skill")
        for skill_path in skill_paths:
            machine.succeed("test ! -e /home/demo/" + skill_path)

        machine.succeed("systemctl restart home-manager-demo.service")
        for skill_path in skill_paths:
            machine.succeed("test -e /home/demo/" + skill_path)
            resolved = machine.succeed(
                as_demo("readlink -f ~/" + skill_path)
            ).strip()
            assert resolved == expected, \
                "HM did not refresh %s: %r != %r" % (skill_path, resolved, expected)

    # --- (9) Theme switch x2: regression guard for the read-only store bug. -
    # cp from the read-only Nix store inherits 444/555 modes, leaving theme
    # files unwritable and colors.toml stale across switches (the bug the
    # --no-preserve=mode patches in pkgs/omarchy.nix fix). Headless mode
    # skips session-integration flakiness (shell IPC, restart commands) and
    # exercises only the file copy/mv/template path the regression affects.
    with machine.nested("theme switch x2: read-only store regression"):
        headless = "OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1"

        machine.succeed(as_demo(headless + " omarchy-theme-set tokyo-night"))
        name = machine.succeed(
            as_demo("cat ~/.local/state/omarchy/current/theme.name")
        ).strip()
        assert name == "tokyo-night", \
            "theme.name is %r, expected tokyo-night" % name

        tokyo_colors = machine.succeed(
            as_demo("cat ~/.local/state/omarchy/current/theme/colors.toml")
        )

        machine.succeed(as_demo(headless + " omarchy-theme-set nord"))
        name = machine.succeed(
            as_demo("cat ~/.local/state/omarchy/current/theme.name")
        ).strip()
        assert name == "nord", "theme.name is %r, expected nord" % name

        nord_colors = machine.succeed(
            as_demo("cat ~/.local/state/omarchy/current/theme/colors.toml")
        )
        assert nord_colors != tokyo_colors, \
            "colors.toml unchanged after theme switch (stale - read-only store bug)"

        nonwritable = machine.succeed(as_demo(
            "find ~/.local/state/omarchy/current/theme/ ! -writable -print 2>/dev/null"
        )).strip()
        assert not nonwritable, \
            "non-writable files in theme dir:\n" + nonwritable

        machine.succeed(
            as_demo("test ! -d ~/.local/state/omarchy/current/next-theme")
        )

    # --- (9b) Plugin clone cp -aL patch invariant (L4 class). -----------
    # omarchy-plugin-clone copies plugin sources out of the store with cp -aL;
    # without --no-preserve=mode the clone lands as 444 files in 555 dirs and
    # the sed -i rename pass aborts (menu: Setup -> Plugin -> Clone). This is
    # a static guard on the packaged script: every cp -aL site must carry the
    # patch (the count tripwire forces re-audit when upstream adds a site).
    # Behavioral L4 coverage lives in (9) — a functional plugin-clone run in
    # the VM is a documented follow-up in TODO.md.
    with machine.nested("plugin-clone --no-preserve=mode guard"):
        clone_script = machine.succeed(
            "cat /run/current-system/sw/share/omarchy/bin/omarchy-plugin-clone"
        )
        assert clone_script.count("cp -aL") == 4, \
            "omarchy-plugin-clone cp -aL site count changed — re-audit the guard"
        assert clone_script.count("cp -aL --no-preserve=mode") == 4, \
            "omarchy-plugin-clone lost --no-preserve=mode on a cp -aL site"

    # --- (10) User config is editable + refresh is idempotent. --------------
    # hyprland.lua and .luarc.json must be regular files (not store symlinks)
    # and writable so the Setup menu and omarchy-refresh-config can overwrite
    # them. omarchy-refresh-config / omarchy-refresh-hyprland must be safe to
    # call repeatedly (idempotent copy from the default tree).
    with machine.nested("user config editability + refresh idempotency"):
        for f in ["hyprland.lua", ".luarc.json"]:
            path = "~/.config/hypr/" + f
            machine.succeed(as_demo("test -f " + path))
            machine.succeed(as_demo("test ! -L " + path))
            machine.succeed(as_demo("test -w " + path))

        # bindings.lua (not hyprland.lua) to avoid clobbering the running
        # session's entry point; Hyprland does not hot-reload Lua anyway.
        machine.succeed(as_demo("omarchy-refresh-config hypr/bindings.lua"))
        machine.succeed(as_demo("omarchy-refresh-config hypr/bindings.lua"))
        machine.succeed(as_demo("test -w ~/.config/hypr/bindings.lua"))

        machine.succeed(as_demo("omarchy-refresh-hyprland"))
        machine.succeed(as_demo("omarchy-refresh-hyprland"))
        machine.succeed(
            as_demo("test -w ~/.local/state/omarchy/toggles/hypr/flags.lua")
        )

    # --- (10b) skel parity seeds + omarchy fonts. ---------------------------
    # Branding files (about/screensaver ASCII art) must exist as writable
    # regular files — omarchy-screensaver loops "File not found" without
    # screensaver.txt. The omarchy icon font and the upstream fontconfig
    # aliases (50-omarchy.conf) must be visible to fontconfig.
    with machine.nested("skel parity seeds + fonts"):
        for path in [
            "~/.config/omarchy/branding/about.txt",
            "~/.config/omarchy/branding/screensaver.txt",
            "~/.local/share/nautilus-python/extensions/localsend.py",
            "~/.local/share/nautilus-python/extensions/transcode.py",
            "~/.local/state/tensaku/state.toml",
        ]:
            machine.succeed(as_demo("test -f " + path))
            machine.succeed(as_demo("test ! -L " + path))
            machine.succeed(as_demo("test -w " + path))
        machine.succeed("fc-list | grep -qi omarchy")
        machine.succeed("test -e /etc/fonts/conf.d/50-omarchy.conf")
        mono = machine.succeed("fc-match monospace").strip()
        assert "JetBrainsMono" in mono, "fc-match monospace -> %r" % mono

        # B16 regression guard: nixpkgs wraps tte (comm = .tte-wrapped), so
        # the screensaver must tolerate the wrapped name in pgrep/pkill -x,
        # else its respawn loop OOMs the session. The pattern must stay
        # <=15 chars — a longer one makes pgrep warn "pattern ... longer
        # than 15 characters" on every call, and this pgrep fires once per
        # second in the wait loop, so the warnings pile up behind the tte
        # canvas and flash at every effect change (found on real AMD
        # hardware).
        script = machine.succeed(
            "cat /run/current-system/sw/share/omarchy/bin/omarchy-screensaver"
        )
        assert '-x "\\.?tte.*"' in script, \
            "screensaver lost the wrapped-tte pgrep/pkill tolerance (B16)"

        # The exact pattern must not trip pgrep's >15-char warning (the
        # source of the console text flashing at effect changes).
        _st, out = machine.execute("pgrep -x '\\.?tte.*' 2>&1")
        assert "longer than" not in out, \
            "pgrep pattern triggers the >15-char warning: %r" % out

        # gpu-screen-recorder wrapper tolerance (same class as B16): the
        # wrapped cmdline is a full store path, so "^gpu-screen-recorder"
        # never matches — recording would start but never stop, and the bar
        # indicator would stay dark (verified on real hardware). The patch
        # must be present in both the script and the QML indicator.
        #
        # The pattern is bracketed ([/]...) — B18, root-caused on real
        # hardware with an instrumented shell: Indicators.qml always instantiates BOTH
        # its horizontal and vertical blocks (visible-gated, Loader still
        # loads), so every indicator exists twice and each instance runs its
        # own statusProc pgrep at session start. pgrep excludes only its own
        # PID, so with a plain pattern the two concurrent pgreps match EACH
        # OTHER's cmdline, both exit 0, and recording latches true at every
        # cold boot (pgrep is slow enough there, ~130ms, that the event-loop-
        # synchronized starts always overlap); the QML's activeStateObserved
        # guard then pins the entry forever. The bracket keeps matching the
        # real recorder while the pgreps' own cmdlines (literal "[/]gpu…")
        # no longer match.
        rec_script = machine.succeed(
            "cat /run/current-system/sw/share/omarchy/bin/omarchy-capture-screenrecording"
        )
        assert '"[/]gpu-screen-recorder "' in rec_script, \
            "capture script lost the self-match-safe wrapped-gsr pkill/pgrep pattern (B18)"
        assert '"^gpu-screen-recorder"' not in rec_script, \
            "capture script still anchors pkill/pgrep to ^gpu-screen-recorder"
        rec_qml = machine.succeed(
            "cat /run/current-system/sw/share/omarchy/shell/plugins/bar/indicators/ScreenRecording.qml"
        )
        assert '"[/]gpu-screen-recorder "' in rec_qml, \
            "bar ScreenRecording indicator lost the self-match-safe pgrep pattern (B18)"

        # B18 behavioral guard, deterministic: the QML pattern must NOT
        # match a cmdline shaped like a sibling pgrep's (which carries the
        # literal bracket text — the cross-match that caused the boot
        # latch), and MUST still match a real wrapped-recorder cmdline.
        # exec -a fakes argv0; the payload is bash (NOT coreutils sleep —
        # nixpkgs coreutils is a multicall binary that re-dispatches on
        # argv0 and dies with "unknown program" under a faked name).
        # systemd-run detaches the fakes from the driver's command session
        # (a plain `cmd &` gets reaped with the driver's process group and
        # its inherited stdout pipe blocks the driver until sleep exits).
        # Absolute paths: systemd's exec search path does not include the
        # NixOS system profile, so bare `bash` fails with 203/EXEC.
        #
        # The fake name must SURVIVE to a steady-state process:
        #  - `bash -c "sleep 30"` exec-optimizes sleep over the shell, wiping
        #    the exec -a argv0 (the fake only existed in a race window —
        #    flaky green/red).
        #  - `exec -a NAME sleep 30` breaks: NixOS coreutils is a multicall
        #    binary that dispatches on argv0 ("unknown program").
        # `sleep 30 & wait` keeps the argv0-renamed bash alive as the parent.
        machine.succeed(
            "systemd-run --quiet --unit=b18-decoy /run/current-system/sw/bin/bash "
            "-c 'exec -a \"pgrep --quiet -f [/]gpu-screen-recorder \" "
            "/run/current-system/sw/bin/bash -c \"/run/current-system/sw/bin/sleep 30 & wait\"'"
        )
        # systemd-run only queues the job — give the unit a moment to exec
        # before judging what the pattern does NOT match.
        machine.sleep(1)
        st_decoy, _ = machine.execute("pgrep --quiet -f '[/]gpu-screen-recorder '")
        assert st_decoy != 0, \
            "gsr pattern matches a sibling-pgrep-shaped cmdline (boot latch regression)"
        machine.succeed(
            "systemd-run --quiet --unit=b18-fake /run/current-system/sw/bin/bash "
            "-c 'exec -a \"/nix/store/fake-gpu-screen-recorder-5.0/bin/.wrapped/gpu-screen-recorder -w eDP-1\" "
            "/run/current-system/sw/bin/bash -c \"/run/current-system/sw/bin/sleep 30 & wait\"'"
        )
        # Same scheduling race on the positive side: poll until the fake
        # recorder shows up instead of racing the unit's exec.
        machine.wait_until_succeeds("pgrep --quiet -f '[/]gpu-screen-recorder '", timeout=10)
        machine.succeed("systemctl stop b18-decoy b18-fake")

        # The menu's `when:` guard must use the self-match-safe variant
        # ([/]...), else the batched bash evaluator's own cmdline matches and
        # "Stop Screenrecording" is visible even when nothing records.
        menu_jsonc = machine.succeed(
            "cat /run/current-system/sw/share/omarchy/default/omarchy/omarchy-menu.jsonc"
        )
        assert "'[/]gpu-screen-recorder '" in menu_jsonc, \
            "menu when-guard lost the self-match-safe gsr pattern"
        assert "^gpu-screen-recorder" not in menu_jsonc, \
            "menu when-guard still anchors to ^gpu-screen-recorder"

    # --- (11) Binary coverage: menu actions, systemd ExecStarts, autostart. -
    # Every command a user can trigger from the Omarchy menu, plus every binary
    # the session autostart and systemd user units reference, must resolve on
    # PATH. This is the "apps don't launch" guard: a missing binary means a
    # menu action or autostart step silently fails.
    with machine.nested("binary coverage from menu + units + autostart"):
        # Blind-spot guard: the quickshell launcher (AppLibrary.qml) starts
        # every picked app via `gtk-launch <desktop-id>` — that call lives in
        # QML, not in menu.jsonc, so the extraction below never sees it.
        machine.succeed("command -v gtk-launch")

        # Same class of blind spot: omarchy-capture-screenshot opens the
        # editor via $OMARCHY_SCREENSHOT_EDITOR (default: tensaku-edit) when
        # the notification is clicked. tensaku-edit is a wrapper shipped by
        # upstream's Arch tensaku package (flags: --filename/--output-filename
        #/--actions-on-enter save-to-clipboard/--save-after-copy/--copy-command
        # wl-copy); the reference lives in a bash script, not in menu.jsonc.
        machine.succeed("command -v tensaku-edit")

        # Same class: the network panel's Wi-Fi band toggle (quattro 14f1bb6c)
        # execs omarchy-network-band from QML (shell/plugins/panels/network/
        # Panel.qml), and the script shells out to `iw dev <device> link` —
        # neither call is visible to the menu/autostart/units extraction.
        machine.succeed("command -v omarchy-network-band")
        machine.succeed("command -v iw")

        # Same class: media keys / omarchy-audio-* scripts shell out to pactl
        # (get-default-sink, set-sink-volume, …). pipewire provides the Pulse
        # protocol, not the CLI — pactl must come from runtimeDeps.
        machine.succeed("command -v pactl")

        # Shell keywords/builtins/system binaries that are always present and
        # are not the *coverage point* of their action.
        SKIP_BUILTINS = {
            "if", "then", "else", "elif", "fi", "do", "done", "for", "while",
            "in", "pkill", "systemctl", "test", "echo", "exit", "return", "cd",
            "export", "local", "source", "set", "sleep", "",
        }

        def extract_commands(action):
            """Return candidate command tokens from a shell action string."""
            cmds = set()
            action = action.replace("\\", "")

            # $(...) subshell commands
            for m in re.finditer(r"\$\(\s*([^\s)]+)", action):
                cmd = m.group(1).strip()
                if cmd and cmd not in SKIP_BUILTINS:
                    cmds.add(cmd)

            # Split on ;, &&, ||, | — take the first word of each segment.
            for seg in re.split(r";|&&|\|\||\|", action):
                seg = seg.strip()
                if not seg:
                    continue
                # Strip leading VAR=value assignments (may chain).
                while True:
                    m = re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg)
                    if not m:
                        break
                    seg = seg[m.end():].strip()
                    if seg.startswith("$("):
                        # Skip past the $(...) — command already extracted above.
                        depth, i = 0, 0
                        while i < len(seg):
                            if seg[i] == "(":
                                depth += 1
                            elif seg[i] == ")":
                                depth -= 1
                                if depth == 0:
                                    break
                            i += 1
                        seg = seg[i + 1:].strip() if i < len(seg) else ""
                    elif seg.split(None, 1):
                        parts = seg.split(None, 1)
                        seg = parts[1].strip() if len(parts) > 1 else ""
                    else:
                        seg = ""
                if not seg:
                    continue
                seg = seg.lstrip("'\"")
                parts = seg.split()
                if not parts:
                    continue
                word = parts[0].strip("'\"")
                if word and word not in SKIP_BUILTINS and not word.startswith("["):
                    cmds.add(word)
            return cmds

        # (a) Menu actions — parse $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc
        menu = machine.succeed(
            as_demo("cat $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc")
        )
        menu = re.sub(r"//.*$", "", menu, flags=re.MULTILINE)
        menu = re.sub(r"/\*.*?\*/", "", menu, flags=re.DOTALL)
        actions = re.findall(r'"action"\s*:\s*"([^"]*)"', menu)
        # Min-count guard: if upstream renames the file or changes the menu
        # schema, extraction silently empties and every PATH check below
        # passes vacuously. Pin a conservative floor (currently 234 actions).
        assert len(actions) >= 100, \
            "menu action extraction yielded only %d (file/schema moved?)" % len(actions)
        candidates = set()
        for action in actions:
            candidates |= extract_commands(action)

        # (b) Autostart.lua — hl.exec_cmd("...") and o.launch("...") strings.
        auto = machine.succeed(
            as_demo("cat $OMARCHY_PATH/default/hypr/autostart.lua")
        )
        autostart_hits = 0
        for pat in [r'hl\.exec_cmd\("([^"]*)"', r'o\.launch\("([^"]*)"']:
            for m in re.finditer(pat, auto):
                autostart_hits += 1
                candidates |= extract_commands(m.group(1))
        # Same vacuity guard for the autostart patterns (currently 8 hits).
        assert autostart_hits >= 5, \
            "autostart exec/launch extraction yielded only %d" % autostart_hits

        # (c) Check each candidate resolves on the session PATH.
        missing = set()
        for cmd in sorted(candidates):
            status, _ = machine.execute(as_demo("command -v " + cmd))
            if status != 0:
                missing.add(cmd)

        # Allowlist of commands from packages not yet ported or that are
        # hardware-specific. Each entry documented with WHY.
        expected_missing = {
            # Dell XPS haptic touchpad firmware tool — not in nixpkgs; only
            # shown in the menu on matching Dell hardware (guarded by `when`).
            "dell-xps-touchpad-haptics",
        }

        unexpected = missing - expected_missing
        assert not unexpected, (
            "commands missing from PATH but not in expected_missing: "
            + ", ".join(sorted(unexpected))
        )
        stale = expected_missing - missing
        if stale:
            machine.log(
                "note: expected_missing entries now resolve (remove them): "
                + ", ".join(sorted(stale))
            )

        # (d) Systemd user unit ExecStarts resolve.
        # The 7 vendored units are path-adapted in pkgs/omarchy.nix (store
        # paths replace /usr/bin/*). Each ExecStart binary must exist.
        unit_names = [
            "bt-agent", "omarchy-fcitx5", "omarchy-migrate-notify",
            "omarchy-recover-internal-monitor", "omarchy-sleep-lock",
            "omarchy-speaker-tuning", "omarchy-tailscale-receive",
        ]
        for unit in unit_names:
            unit_path = "/etc/systemd/user/" + unit + ".service"
            line = machine.succeed(
                "grep -E '^ExecStart=' " + unit_path
            ).strip()
            binary = line.split("=", 1)[1].split()[0]
            machine.succeed("test -x " + binary)

        # (e) omarchy-migrate user unit: native oneshot that closes the
        # "rebuild without omarchy-update skips migrations" gap. Assert it
        # is wired into graphical-session.target and actually ran — the
        # per-user state dir must exist with (baseline) markers.
        machine.succeed(
            "test -L /etc/systemd/user/graphical-session.target.wants/omarchy-migrate.service"
        )
        machine.wait_until_succeeds(
            as_demo("test -d ~/.local/state/omarchy/migrations"), timeout=90
        )
        marker_count = machine.succeed(
            as_demo("ls ~/.local/state/omarchy/migrations | wc -l")
        ).strip()
        assert int(marker_count) > 0, "omarchy-migrate produced no markers"

    # --- (10) Behavioral desktop contract. ----------------------------------
    # Ported concepts from upstream test/acceptance.d: drive the shell over
    # its IPC and assert observable effects (layer namespaces, windows, lock
    # lifecycle log events) instead of mere process existence. Key/text
    # injection uses QMP sendkey (machine.send_key/send_chars) — the kernel
    # evdev path; Wayland virtual-keyboard clients (wtype) cannot type into
    # ext-session-lock surfaces (see the header comment).

    # Layer probe for as_demo (the su -c wrapper forbids single quotes, so
    # the jq program is double-quoted with escaped inner quotes).
    def layer_probe(ns, present):
        op = "> 0" if present else "== 0"
        return as_demo(
            "hyprctl -j layers | jq -e \"[.. | objects | select(.namespace? == \\\""
            + ns + "\\\")] | length " + op + "\""
        )

    # Lock lifecycle evidence (runs as root): the shell logs
    # "omarchy lock <iso> <event>" via console.log, which quickshell writes
    # to its per-instance log — the canonical location (verified identical
    # on a production laptop install, including real lock/unlock cycles).
    # It never reaches journald or /tmp/hyprland.log.
    def lock_log_seen(pattern):
        return "grep -Eq '" + pattern + "' /run/user/1000/quickshell/by-id/*/log.log"

    with machine.nested("menu IPC: apps search launches the top hit"):
        machine.succeed(as_demo("omarchy-menu summon apps"))
        machine.wait_until_succeeds(layer_probe("omarchy-menu", True), timeout=30)
        machine.send_chars("foot")
        machine.send_key("ret")
        machine.wait_until_succeeds(
            as_demo("hyprctl -j clients | jq -e \"map(select(.class == \\\"foot\\\")) | length > 0\""),
            timeout=60,
        )
        machine.screenshot("behavioral-menu-apps-foot")
        # Upstream asserts the menu closes after launching; under QEMU the
        # layer occasionally lingers (no focus-follows-launch on a headless
        # seat), so treat close as best-effort and force it over IPC. The
        # asserted contract is the launch effect above.
        try:
            machine.wait_until_succeeds(layer_probe("omarchy-menu", False), timeout=20)
        except Exception:
            machine.log("note: menu layer still open after launch; hiding via IPC")
            machine.succeed(as_demo("omarchy-shell shell hide omarchy.menu"))
            machine.wait_until_succeeds(layer_probe("omarchy-menu", False), timeout=15)
        # Cleanup: kill every foot* process (deterministic). The window's
        # owning PID may be an app2unit/uwsm scope, so killing the single
        # hyprctl-reported PID is not enough; pkill the process family.
        machine.log(
            "foot clients before cleanup: "
            + machine.succeed(as_demo("hyprctl -j clients | jq -c \"map(select(.class == \\\"foot\\\"))\""))
        )
        machine.succeed(
            as_demo("pkill -x foot; pkill -x footclient; pkill -x foot-server; true")
        )
        machine.wait_until_succeeds(
            as_demo("hyprctl -j clients | jq -e \"map(select(.class == \\\"foot\\\")) | length == 0\""),
            timeout=30,
        )

    with machine.nested("notification renders (OCR) and dismisses"):
        machine.succeed(as_demo("omarchy-shell notifications dismissAll || true"))
        machine.succeed(
            as_demo("omarchy-notification-send \"Acceptance notification\" \"Shell notification rendering\" --expire-time=120000")
        )
        machine.wait_until_succeeds(layer_probe("omarchy-notifications", True), timeout=30)
        machine.screenshot("behavioral-notification")
        # Rendered content, not just the surface: OCR the visible popup.
        # grim needs WAYLAND_DISPLAY (session is wayland-1, not the
        # wayland-0 default).
        # The raw full-screen `--psm 11` pipeline cannot read
        # the BOLD title reliably (measured in a 20-iteration lab inside
        # this VM: 0/10 title matches while the popup was clearly visible,
        # body 10/10; fc-match resolves LiberationSans-Bold correctly, so
        # it is OCR fragility, not a font fallback). Grayscale + 200%
        # upscale + -normalize made the title 10/10 in the same run, same
        # popup. A region crop proved unnecessary (10/10 without), so the
        # pipeline stays layout-independent (no hardcoded screen region).
        ocr_chain = (
            "WAYLAND_DISPLAY=wayland-1 grim /tmp/notif.png"
            + " && magick /tmp/notif.png -colorspace Gray -resize 200% -normalize /tmp/notif-proc.png"
            + " && tesseract /tmp/notif-proc.png stdout --psm 11 2>/dev/null"
        )
        try:
            machine.wait_until_succeeds(
                as_demo(ocr_chain + " | tee /tmp/notif-ocr.txt | grep -qi \"Acceptance notification\" && grep -qi \"Shell notification rendering\" /tmp/notif-ocr.txt"),
                timeout=30,
            )
        except Exception:
            # Failure artifacts: the check log must explain
            # the mismatch — raw OCR text, word-level TSV confidence and
            # the captured PNG (base64) from the last failed attempt.
            machine.log("notification OCR raw text: " + machine.succeed("cat /tmp/notif-ocr.txt 2>/dev/null || true"))
            machine.log("notification OCR tsv: " + machine.succeed("tesseract /tmp/notif-proc.png stdout --psm 11 tsv 2>/dev/null | awk -F'\\t' '$1 == 5 {print $11, $12}' || true"))
            machine.log("notification png base64: " + machine.succeed("base64 -w0 /tmp/notif.png || true"))
            raise

        # Note: ~/.local/state/omarchy/notifications.json is NOT a usable
        # secondary assertion channel — a displayed popup lives in
        # popupModel, never in the persisted pending/past lists, and
        # dismissAll clears both (verified empirically).
        machine.succeed(as_demo("omarchy-shell notifications dismissAll"))
        machine.wait_until_succeeds(layer_probe("omarchy-notifications", False), timeout=30)
        # Negative fixture: the SAME OCR pipeline + matcher must FAIL when
        # no popup is visible (proves the assertion has teeth, per the
        # acceptance criteria).
        machine.fail(as_demo(ocr_chain + " | grep -qi \"Acceptance notification\""))
        machine.fail(as_demo(ocr_chain + " | grep -qi \"Shell notification rendering\""))

    with machine.nested("volume OSD appears on sink change and hides"):
        machine.succeed(as_demo("pactl load-module module-null-sink sink_name=acceptance"))
        machine.succeed(as_demo("pactl set-default-sink acceptance"))
        # The OSD is not reactive: omarchy-audio-output-volume (the keybind
        # path) changes the volume AND shows the OSD. Each retry re-fires
        # the popup (its hide timer restarts), so the layer probe runs
        # while the card is still visible.
        machine.wait_until_succeeds(
            as_demo("omarchy-audio-output-volume raise && hyprctl -j layers | jq -e \"[.. | objects | select(.namespace? == \\\"omarchy-osd\\\")] | length > 0\""),
            timeout=30,
        )
        machine.screenshot("behavioral-osd")
        machine.wait_until_succeeds(layer_probe("omarchy-osd", False), timeout=60)

    with machine.nested("lock authenticates with the user password"):
        machine.succeed(as_demo("omarchy-shell lock lock"))
        machine.wait_until_succeeds(
            lock_log_seen("omarchy lock .*lock-requested"), timeout=30
        )
        # The ext-session-lock surface is really up: the compositor confirms
        # the secure state (on this build the lock goes lock-requested ->
        # secure=true; session-locked=true is not emitted).
        try:
            machine.wait_until_succeeds(
                lock_log_seen("omarchy lock .*secure=true"), timeout=30
            )
        except Exception:
            machine.log(
                "lock log dump: "
                + machine.execute("grep 'omarchy lock' /run/user/1000/quickshell/by-id/*/log.log")[1]
            )
            raise
        machine.screenshot("behavioral-lock")
        machine.send_chars("demo")
        machine.send_key("ret")
        machine.wait_until_succeeds(
            lock_log_seen("omarchy lock .*unlocked"), timeout=30
        )

    with machine.nested("polkit prompt authenticates (agent round trip)"):
        machine.succeed("rm -f /tmp/pkexec.out /tmp/pkexec.err /tmp/pkrun.sh")
        # pkexec must run inside the systemd user manager cgroup (its polkit
        # subject then resolves to the manager session the quickshell agent
        # serves — `su -` resolves to no session and pkexec fails instantly).
        # Spawning via hyprctl exec_cmd makes pkexec a Hyprland child — same
        # as a real keybind-launched privileged action. With the Lua config,
        # `hyprctl dispatch X` evals as Lua `hl.dispatch(X)`, so X must be a
        # dispatcher object (hl.dsp.exec_cmd), not the legacy `exec` keyword.
        machine.succeed(
            "printf '%s\\n' 'pkexec id -u >/tmp/pkexec.out 2>/tmp/pkexec.err' > /tmp/pkrun.sh && chmod +x /tmp/pkrun.sh"
        )
        machine.succeed(
            as_demo("hyprctl dispatch \"hl.dsp.exec_cmd(\\\"/tmp/pkrun.sh\\\")\"")
        )
        try:
            machine.wait_until_succeeds(layer_probe("omarchy-polkit", True), timeout=30)
        except Exception:
            machine.log("pkexec.err: " + machine.execute("cat /tmp/pkexec.err")[1])
            machine.log(
                "sessions: " + machine.execute("loginctl list-sessions")[1]
            )
            raise
        machine.screenshot("behavioral-polkit")
        machine.send_chars("demo")
        machine.send_key("ret")
        machine.wait_until_succeeds("grep -q \"^0$\" /tmp/pkexec.out", timeout=30)
        machine.wait_until_succeeds(layer_probe("omarchy-polkit", False), timeout=30)

    # --- (8) Screenshot for diagnostics. -----------------------------------
    # Under QEMU without virgil the Aquamarine framebuffer is near-empty (see
    # tests/desktop.nix); kept for manual inspection via `nix log`.
    machine.screenshot("omarchy-ux")
  '';
}
