# NixOS test: Omarchy Fish profile (omarchy.fish.enable) behavioral test.
#
# Where checks.omarchy-fish-package / omarchy-fish-parity guard the vendored
# tree and checks.omarchy-fish-module covers the eval-time wiring (including
# the default-OFF state on the demo config), this test boots a VM with the
# profile ON and fish as the demo user's login shell, and asserts the
# runtime behavior end to end:
#   - fish is the login shell; the vendor_* dirs land in the system profile;
#   - an interactive fish session sees the omarchy functions (including the
#     Quattro bash-parity helpers cy/mup/rsw/lsw/dsw/tds), the omarchy
#     completion is registered, and EDITOR/SUDO_EDITOR arrive via PAM
#     (environment.sessionVariables -> /etc/pam/environment -> pam_env);
#   - user functions in ~/.config/fish/functions override the vendor copies
#     (and removing the override restores the vendor copy);
#   - the `# omarchy:args=` completion contract resolves against a hermetic
#     fixture bin dir (mirrors the upstream PR #7 fixture approach);
#   - the external binaries the vendored functions call are on PATH.
#
# No graphical session: multi-user.target is enough — the profile is shell
# plumbing, not desktop. Modelled on tests/desktop.nix's node structure.
{
  pkgs,
  lib,
  omarchy,
  home-manager,
  ...
}:

{
  name = "omarchy-fish";
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

      virtualisation.memorySize = 2048;
      virtualisation.cores = 2;

      omarchy.enable = true;
      omarchy.managedPackagesFile = null; # hermetic check (host /etc must not leak in)
      omarchy.full_name = "Test User";
      omarchy.email_address = "test@omarchy-nix.invalid";
      omarchy.fish.enable = true;

      users.users.demo = {
        isNormalUser = true;
        uid = 1000;
        password = "demo";
        shell = pkgs.fish;
        extraGroups = [ "wheel" ];
      };

      home-manager.users.demo = {
        imports = [ omarchy.homeManagerModules.default ];
        home.username = "demo";
        home.homeDirectory = "/home/demo";
        home.stateVersion = "26.05";
        omarchy.enable = true;
      };

      # No display manager in this test (see tests/desktop.nix for why SDDM
      # is disabled rather than driven headlessly).
      services.displayManager.sddm.enable = false;
    };

  testScript = ''
    machine.start()

    machine.wait_for_unit("multi-user.target")

    def as_demo(cmd):
        # su - opens a PAM session: pam_env applies /etc/pam/environment
        # (environment.sessionVariables), so the demo process sees the
        # session env a real login gets. cmd runs via the login shell
        # (fish); it is single-quote wrapped, so use double quotes inside.
        return "su - demo -c '" + cmd + "'"

    # --- (1) Login shell + vendor dirs in the system profile. --------------
    shell = machine.succeed("getent passwd demo").strip().split(":")[-1]
    assert shell.endswith("/bin/fish"), "demo login shell is not fish: %r" % shell
    for fn in ["cy", "mup", "rsw", "lsw", "dsw", "tds", "try"]:
        machine.succeed(
            "test -e /run/current-system/sw/share/fish/vendor_functions.d/%s.fish" % fn
        )
    machine.succeed("test -e /run/current-system/sw/share/fish/vendor_completions.d/omarchy.fish")
    machine.succeed("test -e /run/current-system/sw/share/fish/vendor_conf.d/init.fish")

    # --- (2) Interactive session: functions, EDITOR, completion. -----------
    out = machine.succeed(
        as_demo("fish -ic \"functions -q cy mup rsw lsw dsw tds; and echo FUNCTIONS-OK\"")
    )
    assert "FUNCTIONS-OK" in out, "omarchy fish functions not visible: %r" % out

    # EDITOR/SUDO_EDITOR mirror default/bash/envs and arrive via PAM
    # (sessionVariables -> /etc/pam/environment -> pam_env on the su session).
    editor = machine.succeed(as_demo("printenv EDITOR")).strip()
    assert editor == "omarchy-launch-editor --inline", \
        "EDITOR wrong in login session: %r" % editor
    sudo_editor = machine.succeed(as_demo("printenv SUDO_EDITOR")).strip()
    assert sudo_editor == "omarchy-launch-editor --inline", \
        "SUDO_EDITOR wrong in login session: %r" % sudo_editor

    # The completion file autoloads on the first completion request for
    # `omarchy`, so `complete -c` alone shows nothing — request a completion
    # first (against the real $OMARCHY_PATH/bin on the session PATH), then
    # inspect the registered definition. Script file to keep quoting sane.
    machine.succeed(
        "printf 'complete -C \"omarchy \"\\ncomplete -c omarchy\\n' > /home/demo/completion-load.fish"
    )
    machine.succeed("chown demo:users /home/demo/completion-load.fish")
    out = machine.succeed(as_demo("fish /home/demo/completion-load.fish"))
    assert "theme" in out, \
        "omarchy subcommand completion returned no candidates: %r" % out
    assert "__omarchy_complete" in out, "omarchy completion not registered: %r" % out

    # --- (3) Override precedence: user functions beat vendor copies. -------
    machine.succeed(as_demo("mkdir -p /home/demo/.config/fish/functions"))
    machine.succeed(
        "printf 'function cy\\n    echo USER-OVERRIDE\\nend\\n' > /home/demo/.config/fish/functions/cy.fish"
    )
    machine.succeed("chown -R demo:users /home/demo/.config/fish")
    out = machine.succeed(as_demo("fish -ic \"functions cy\""))
    assert "USER-OVERRIDE" in out, "user cy.fish did not win over vendor copy: %r" % out
    machine.succeed(as_demo("rm /home/demo/.config/fish/functions/cy.fish"))
    out = machine.succeed(as_demo("fish -ic \"functions cy\""))
    assert "codex" in out and "USER-OVERRIDE" not in out, \
        "vendor cy.fish not restored after removing override: %r" % out

    # --- (4) `# omarchy:args=` completion contract against a fixture. ------
    # Fake bin dir with an `omarchy` trampoline and an omarchy-theme-set
    # carrying an args spec; prepended to PATH inside the fixture script so
    # the completion resolves bin_dir to the fixture (not $OMARCHY_PATH/bin).
    machine.succeed("mkdir -p /home/demo/fixture-bin")
    machine.succeed("printf '#!/bin/sh\\n# fixture\\n' > /home/demo/fixture-bin/omarchy")
    machine.succeed(
        "printf '#!/bin/sh\\n# omarchy:args=<alpha|beta|gamma>\\n' > /home/demo/fixture-bin/omarchy-theme-set"
    )
    machine.succeed("chmod +x /home/demo/fixture-bin/omarchy /home/demo/fixture-bin/omarchy-theme-set")
    machine.succeed(
        "printf 'set -gx PATH /home/demo/fixture-bin $PATH\\ncomplete -C \"omarchy theme set \"\\n' > /home/demo/completion-test.fish"
    )
    machine.succeed("chown -R demo:users /home/demo/fixture-bin /home/demo/completion-test.fish")
    out = machine.succeed(as_demo("fish /home/demo/completion-test.fish"))
    for candidate in ["alpha", "beta", "gamma"]:
        assert candidate in out.split(), \
            "omarchy:args= candidate %r missing from completion: %r" % (candidate, out)

    # --- (5) External binaries the vendored functions call. ----------------
    # parted (format-drive), rsync+ssh (rsw watchers), inotifywait+setsid
    # (rsw watcher loop), scp (sff), file+bat (ff preview branches).
    for binary in ["parted", "rsync", "inotifywait", "setsid", "ssh", "scp", "file", "bat"]:
        machine.succeed("command -v " + binary)
  '';
}
