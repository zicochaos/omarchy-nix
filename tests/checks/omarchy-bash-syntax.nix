# bash -n over the packaged shell code: every bin/ script with a bash
# shebang (the vendored scripts and everything pkgs/omarchy.nix writes
# or patches), the sourced omarchy-nix-pkglib library, the vendored
# migrations and the NixOS migration adapters (both run via bash). A
# patch or heredoc that breaks the syntax fails here instead of at
# runtime; the per-set floors fail an empty or shrunken glob.
{
  self,
  pkgs,
  system,
  ...
}:
let
  root = "${self.packages.${system}.omarchy}/share/omarchy";
in
pkgs.runCommand "omarchy-bash-syntax-check" { } ''
  bad=0
  check() { # <set> <min> <files...>
    local set=$1 min=$2 f n=0
    shift 2
    for f in "$@"; do
      n=$((n + 1))
      bash -n "$f" 2>syntax.err || { echo "bash -n: $f"; cat syntax.err; bad=1; }
    done
    if ((n < min)); then
      echo "$set: only $n scripts checked (want at least $min)"
      bad=1
    fi
    echo "$set: $n scripts"
  }

  scripts=()
  for f in ${root}/bin/*; do
    [[ -f $f ]] || continue
    IFS= read -r first <"$f" || true
    if [[ $first =~ ^\#!.*/bash([[:space:]]|$) || $first =~ ^\#!.*env[[:space:]]+bash([[:space:]]|$) ]]; then
      scripts+=("$f")
    fi
  done
  check "bin (bash shebang)" 450 "''${scripts[@]}"
  check "bin library" 1 ${root}/bin/omarchy-nix-pkglib
  check "migrations" 120 ${root}/migrations/*.sh
  check "migration adapters" ${toString (builtins.length (builtins.attrNames (builtins.readDir ../../pkgs/migrations-nix)))} ${root}/migrations-nix/*.sh

  [[ $bad == 0 ]] || exit 1
  touch $out
''
