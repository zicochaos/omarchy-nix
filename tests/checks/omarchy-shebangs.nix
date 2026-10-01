# Shebang coverage: every executable shipped in the
# package must resolve to a Nix store interpreter — no /usr/bin
# or /usr/bin/env leftovers (NixOS has neither).
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
in
pkgs.runCommand "omarchy-shebang-check" { } ''
  # List first, then loop: a find failing inside `< <(find ...)` would
  # go unnoticed (process substitution status is ignored), and an empty
  # list would pass vacuously, hence the floor below (481 scripts carry
  # a shebang as of 8b4eae6).
  find ${omarchyPkg} -type f -perm -u+x > executables.txt
  bad=0
  scripts=0
  while IFS= read -r f; do
    first=$(head -n1 "$f" || true)
    case "$first" in
      '#!'*) scripts=$((scripts + 1)) ;;
      *) continue ;;
    esac
    interp=''${first#\#!}
    interp=''${interp#"''${interp%%[![:space:]]*}"}
    case "$interp" in
      /nix/store/*) ;;
      *)
        echo "unpatched interpreter: $f -> $first"
        bad=1
        ;;
    esac
  done < executables.txt
  if [ "$scripts" -lt 400 ]; then
    echo "only $scripts scripts with a shebang (expected >= 400; tree moved?)"
    exit 1
  fi
  [[ $bad == 0 ]] || exit 1
  touch $out
''
