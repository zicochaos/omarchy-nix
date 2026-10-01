# Home-Manager activation, executed for real: standalone Home Manager
# configurations importing self.homeModules.default are built and their
# activation packages run (repeatedly, like successive switches) against a
# throwaway $HOME inside the build sandbox. The activation script resets
# PATH to Home Manager's own tool set, so every step runs with the PATH it
# gets in production.
#
# managed: Home Manager programs own files omarchy also seeds (git,
#   starship, bash, a whole foot config dir). The seed must leave them to
#   HM, so the second activation passes HM's own link-target check.
# plain: the seeding itself -- monitors.lua from omarchy.scale/monitors,
#   ~/.bashrc only when absent (file or symlink kept), user edits survive,
#   legacy omarchy store links replaced while foreign links stay, user
#   skill dirs moved aside, a failed nvim seed retried, and a dry run
#   that writes nothing.
{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
let
  inherit (pkgs) lib;
  omarchyTree = "${self.packages.${system}.omarchy}/share/omarchy";
  fmt = import ../../modules/lib/omarchy-formats.nix { inherit lib; };

  mkHome =
    module:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeModules.default
        {
          home.username = "omarchy";
          home.homeDirectory = "/home/omarchy";
          home.stateVersion = "26.05";
          omarchy.enable = true;
        }
        module
      ];
    }).activationPackage;

  managed = mkHome {
    programs.git = {
      enable = true;
      settings.user.name = "HM Test";
    };
    programs.starship = {
      enable = true;
      settings.add_newline = false;
    };
    programs.bash.enable = true;
    # A whole directory owned by HM, without the file omarchy seeds into it.
    xdg.configFile.foot.source = pkgs.writeTextDir "custom.ini" "# hm-owned foot dir\n";
  };

  monitors = [ "DP-1, 2560x1440@120, 0x0, 1" ];
  monitorsLua = pkgs.writeText "monitors.lua" (
    fmt.monitorsLuaText {
      scale = 2;
      inherit monitors;
    }
  );

  # The real omarchy-nvim setup, except that it fails half-way (a partial
  # ~/.config/nvim, exit 1) while the file named by $OMARCHY_TEST_NVIM_FAIL
  # exists.
  nvimFlaky = pkgs.writeShellScriptBin "omarchy-nvim-setup" ''
    if [ -e "''${OMARCHY_TEST_NVIM_FAIL:-/nonexistent}" ]; then
      mkdir -p "$HOME/.config/nvim"
      echo "-- half-seeded" > "$HOME/.config/nvim/partial.lua"
      echo "simulated omarchy-nvim-setup failure" >&2
      exit 1
    fi
    exec ${self.packages.${system}.omarchy-nvim}/bin/omarchy-nvim-setup "$@"
  '';

  plain = mkHome {
    omarchy.scale = 2;
    omarchy.monitors = monitors;
    omarchy.nvimPackage = nvimFlaky;
  };

  foreignKitty = pkgs.writeText "kitty.conf" "# owned by another tool\n";
  storeBashrc = pkgs.writeText "bashrc" "# owned by another tool\n";

  # The activation's Nix plumbing (store sanity check, profile and GC-root
  # handling) needs a Nix daemon the sandbox does not have. HM appends the
  # directory holding nix-env to the activation PATH; these stubs are all
  # it holds. nix-store records GC roots as plain links, so the next
  # activation finds its previous generation as on a real system.
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
pkgs.runCommand "omarchy-hm-activation-check" { } ''
  set -euo pipefail
  export PATH=${nixStubs}/bin:$PATH USER=omarchy SKIP_SANITY_CHECKS=1
  fail() { echo "FAIL: $*" >&2; exit 1; }
  use_home() {
    export HOME=$TMPDIR/$1
    mkdir -p "$HOME/.local/state/nix/profiles"
  }
  # A run's combined output lands in $TMPDIR/activate.log; a failing run
  # prints it, so Home Manager's own error reaches the build log.
  activate() {
    "$1/activate" --driver-version 1 > "$TMPDIR/activate.log" 2>&1 \
      || { cat "$TMPDIR/activate.log" >&2; return 1; }
  }
  hm_link() { [[ "$(readlink "$1")" == ${builtins.storeDir}/*-home-manager-files/* ]]; }
  regular() { [ -f "$1" ] && [ ! -L "$1" ] && [ -w "$1" ]; }

  # --- managed: HM-owned targets are never seeded over -----------------
  use_home managed
  activate ${managed} || fail "managed: first activation failed"
  activate ${managed} \
    || fail "managed: second activation failed (a seed replaced an HM-managed file)"
  for f in .config/git/config .config/starship.toml .bashrc .config/foot; do
    hm_link "$HOME/$f" || fail "managed: ~/$f is not Home Manager's link"
  done
  grep -q "HM Test" "$HOME/.config/git/config" || fail "managed: git config lost HM's content"
  [ ! -e "$HOME/.config/foot/foot.ini" ] || fail "managed: foot.ini seeded into HM's foot dir"
  regular "$HOME/.config/hypr/hyprland.lua" || fail "managed: unrelated seeds missing"

  # --- plain: first activation -------------------------------------------
  use_home plain
  # Pre-existing state: a user-owned skill directory, a symlink some other
  # tool owns (into the store, but not into an omarchy tree), and a legacy
  # link into the omarchy tree from module versions that used
  # xdg.configFile.
  mkdir -p "$HOME/.claude/skills/omarchy" "$HOME/.config/kitty" "$HOME/.config/hypr"
  echo "user skill" > "$HOME/.claude/skills/omarchy/notes.md"
  ln -s ${foreignKitty} "$HOME/.config/kitty/kitty.conf"
  ln -s ${omarchyTree}/config/hypr/bindings.lua "$HOME/.config/hypr/bindings.lua"
  export OMARCHY_TEST_NVIM_FAIL=$TMPDIR/nvim-fail
  touch "$OMARCHY_TEST_NVIM_FAIL"
  activate ${plain} || fail "plain: first activation failed"
  grep -q "omarchy-nvim-setup failed" "$TMPDIR/activate.log" || fail "plain: failed nvim seed was silent"

  regular "$HOME/.bashrc" && cmp -s ${omarchyTree}/default/bashrc "$HOME/.bashrc" \
    || fail "plain: absent ~/.bashrc not seeded from upstream default/bashrc"
  regular "$HOME/.config/hypr/monitors.lua" \
    && cmp -s ${monitorsLua} "$HOME/.config/hypr/monitors.lua" \
    && grep -qx 'local omarchy_gdk_scale = 2' "$HOME/.config/hypr/monitors.lua" \
    && grep -qF 'output = "DP-1"' "$HOME/.config/hypr/monitors.lua" \
    || fail "plain: monitors.lua does not reflect omarchy.scale/omarchy.monitors"
  regular "$HOME/.config/hypr/bindings.lua" \
    && cmp -s ${omarchyTree}/config/hypr/bindings.lua "$HOME/.config/hypr/bindings.lua" \
    || fail "plain: legacy omarchy store link not replaced by a writable copy"
  [ "$(readlink "$HOME/.config/kitty/kitty.conf")" = ${foreignKitty} ] \
    || fail "plain: a symlink owned by another tool was replaced"
  [ "$(readlink -f "$HOME/.claude/skills/omarchy")" = "$(readlink -f ${omarchyTree}/default/agents/skills/omarchy)" ] \
    || fail "plain: skill link does not point at the package skill"
  backups=("$HOME"/.claude/skills/omarchy.hm-backup-*)
  [ ''${#backups[@]} = 1 ] && [ "$(cat "''${backups[0]}/notes.md")" = "user skill" ] \
    || fail "plain: user skill dir not moved aside intact"
  [ ! -e "$HOME/.config/nvim" ] || fail "plain: failed nvim seed left ~/.config/nvim behind"

  # --- plain: second activation keeps user state, retries nvim ----------
  echo "-- user edit" >> "$HOME/.config/hypr/input.lua"
  echo "-- user edit" >> "$HOME/.config/hypr/monitors.lua"
  cp "$HOME/.config/hypr/input.lua" "$TMPDIR/input.lua"
  cp "$HOME/.config/hypr/monitors.lua" "$TMPDIR/monitors.lua"
  echo "# user bashrc" > "$HOME/.bashrc"
  rm "$OMARCHY_TEST_NVIM_FAIL"
  activate ${plain} || fail "plain: second activation failed"

  cmp -s "$TMPDIR/input.lua" "$HOME/.config/hypr/input.lua" || fail "plain: user edit to input.lua lost"
  cmp -s "$TMPDIR/monitors.lua" "$HOME/.config/hypr/monitors.lua" || fail "plain: user edit to monitors.lua lost"
  [ "$(cat "$HOME/.bashrc")" = "# user bashrc" ] || fail "plain: existing ~/.bashrc file overwritten"
  [ -f "$HOME/.config/nvim/init.lua" ] && [ ! -e "$HOME/.config/nvim/partial.lua" ] \
    || fail "plain: nvim seed not retried after the failed attempt"
  [ "$(readlink "$HOME/.config/nvim/lua/plugins/theme.lua")" = ../../../../.local/state/omarchy/current/theme/neovim.lua ] \
    || fail "plain: nvim theme.lua link missing"
  [ -z "$(find "$HOME/.config/nvim" ! -type l ! -writable)" ] || fail "plain: nvim seed left read-only files"
  [ -d "$HOME/.local/share/nvim" ] || fail "plain: nvim data dir not seeded"
  [ ! -e "$HOME/.local/state/omarchy/nvim-seed" ] || fail "plain: nvim staging dir left behind"
  backups=("$HOME"/.claude/skills/omarchy.hm-backup-*)
  [ ''${#backups[@]} = 1 ] || fail "plain: managed skill link moved aside again"

  # --- plain: a symlinked ~/.bashrc stays, even one into the store -------
  rm "$HOME/.bashrc"
  ln -s ${storeBashrc} "$HOME/.bashrc"
  activate ${plain} || fail "plain: third activation failed"
  [ "$(readlink "$HOME/.bashrc")" = ${storeBashrc} ] || fail "plain: symlinked ~/.bashrc replaced"
  ln -sfn /nonexistent/dotfiles/bashrc "$HOME/.bashrc"
  activate ${plain} || fail "plain: activation with a dangling ~/.bashrc link failed"
  [ "$(readlink "$HOME/.bashrc")" = /nonexistent/dotfiles/bashrc ] || fail "plain: dangling ~/.bashrc link replaced"

  # --- plain: a dry run writes nothing ----------------------------------
  # Give every omarchy step work to do: a missing seed, no nvim config, a
  # user skill dir, a missing first-run marker.
  rm "$HOME/.config/hypr/input.lua"
  rm -rf "$HOME/.config/nvim"
  rm "$HOME/.codex/skills/omarchy"
  mkdir "$HOME/.codex/skills/omarchy"
  echo "user skill" > "$HOME/.codex/skills/omarchy/notes.md"
  rm "$HOME/.local/state/omarchy/done/voxtype-install-invitation"
  snapshot() {
    (cd "$HOME" && find . -printf '%p %y %m %l\n' | sort && find . -type f -exec sha256sum {} + | sort)
  }
  snapshot > "$TMPDIR/before"
  DRY_RUN=1 activate ${plain} || fail "plain: dry run failed"
  snapshot > "$TMPDIR/after"
  diff "$TMPDIR/before" "$TMPDIR/after" || fail "plain: dry run changed \$HOME"
  # The live run then does the work the dry run only announced.
  activate ${plain} || fail "plain: activation after the dry run failed"
  regular "$HOME/.config/hypr/input.lua" || fail "plain: missing seed not restored"
  [ -f "$HOME/.config/nvim/init.lua" ] || fail "plain: nvim not reseeded"
  [ -L "$HOME/.codex/skills/omarchy" ] || fail "plain: codex skill link not restored"
  backups=("$HOME"/.codex/skills/omarchy.hm-backup-*)
  [ "$(cat "''${backups[0]}/notes.md")" = "user skill" ] || fail "plain: codex skill dir not moved aside"
  [ -e "$HOME/.local/state/omarchy/done/voxtype-install-invitation" ] || fail "plain: marker not restored"
  touch $out
''
