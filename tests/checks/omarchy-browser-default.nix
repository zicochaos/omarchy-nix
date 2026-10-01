# Default browser (upstream provision-user parity), executed through the
# real Home Manager activation package of a standalone configuration. Its
# PATH is Home Manager's own tool set (emptyActivationPath), as in
# production: no xdg-settings there, so the step must call it by store
# path. The xdg-utils package is replaced by a deterministic stub (through
# the configuration's pkgs, never through PATH), so a missing desktop
# session cannot make this pass merely because xdg-settings silently
# failed.
{
  self,
  inputs,
  pkgs,
  ...
}:
let
  xdgUtilsStub = pkgs.writeShellScriptBin "xdg-settings" ''
    [[ ! -v BROWSER ]] || exit 90
    case "$1:$2" in
      get:default-web-browser)
        [[ ''${BROWSER_QUERY_FAIL:-0} == 0 ]] || exit 1
        cat "$BROWSER_CHOICE"
        ;;
      set:default-web-browser)
        printf '%s\n' "$3" > "$BROWSER_CHOICE"
        echo set >> "$BROWSER_WRITES"
        ;;
      *) exit 91 ;;
    esac
  '';

  mkHome =
    module:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.default
        {
          # Standalone Home Manager re-imports nixpkgs; force the module
          # argument so the module's pkgs.xdg-utils is the stub.
          _module.args.pkgs = pkgs.lib.mkForce (pkgs // { xdg-utils = xdgUtilsStub; });
          home.username = "omarchy";
          home.homeDirectory = "/home/omarchy";
          home.stateVersion = "26.05";
          omarchy.enable = true;
          omarchy.nvimPackage = null;
        }
        module
      ];
    }).activationPackage;

  plain = mkHome { };
  # Home Manager owns ~/.config/mimeapps.list: xdg-settings would replace
  # that link with a file and the next switch would abort on it.
  hmMimeApps = mkHome {
    xdg.mimeApps = {
      enable = true;
      defaultApplications."text/plain" = [ "nvim.desktop" ];
    };
  };

  # The activation's Nix plumbing (store sanity check, profile and GC-root
  # handling) needs a Nix daemon the sandbox does not have; see
  # omarchy-hm-activation.nix.
  nixStubs = pkgs.runCommand "hm-activation-nix-stubs" { } ''
    mkdir -p $out/bin
    for tool in nix nix-build nix-env; do
      printf '#!%s\nexit 0\n' ${pkgs.runtimeShell} > $out/bin/$tool
    done
    cat > $out/bin/nix-store <<'EOF'
    #!${pkgs.runtimeShell}
    [ "$1" = --realise ] && [ "$3" = --add-root ] || exit 0
    mkdir -p "$(dirname "$4")"
    ln -sfn "$2" "$4"
    EOF
    chmod +x $out/bin/*
  '';
in
pkgs.runCommand "omarchy-browser-default-check" { } ''
  set -euo pipefail
  trap 'echo "FAIL: $BASH_COMMAND" >&2; trap - ERR' ERR
  export PATH=${nixStubs}/bin:$PATH USER=omarchy SKIP_SANITY_CHECKS=1
  activate() {
    mkdir -p "$HOME/.local/state/nix/profiles"
    "$1/activate" --driver-version 1 > "$TMPDIR/activate.log" 2>&1 \
      || { cat "$TMPDIR/activate.log" >&2; return 1; }
  }
  export BROWSER=omarchy-launch-browser
  export BROWSER_CHOICE="$TMPDIR/browser-choice"
  export BROWSER_WRITES="$TMPDIR/browser-writes"
  : > "$BROWSER_WRITES"

  export HOME=$TMPDIR/plain
  printf '%s\n' firefox.desktop > "$BROWSER_CHOICE"
  activate ${plain}
  test "$(cat "$BROWSER_CHOICE")" = firefox.desktop
  test ! -s "$BROWSER_WRITES"

  : > "$BROWSER_CHOICE"
  activate ${plain}
  test "$(cat "$BROWSER_CHOICE")" = chromium.desktop
  test "$(wc -l < "$BROWSER_WRITES")" = 1
  activate ${plain}
  test "$(wc -l < "$BROWSER_WRITES")" = 1

  BROWSER_QUERY_FAIL=1 activate ${plain}
  test "$(wc -l < "$BROWSER_WRITES")" = 1

  export HOME=$TMPDIR/hm-mimeapps
  : > "$BROWSER_CHOICE"
  : > "$BROWSER_WRITES"
  activate ${hmMimeApps}
  activate ${hmMimeApps}
  test ! -s "$BROWSER_WRITES"
  [[ "$(readlink "$HOME/.config/mimeapps.list")" == ${builtins.storeDir}/*-home-manager-files/* ]]
  touch $out
''
