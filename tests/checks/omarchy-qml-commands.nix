# Shell exec coverage: every literal program the vendored Quickshell
# tree starts must resolve on the desktop's PATH. Scans
# shell/**/*.{qml,js} for the first argv element of
#   command: [ "X", … ]                 (Process objects, plans in JS)
#   [Quickshell.|Util.]execDetached([ "X", … ])
# (multi-line forms included) and looks each X up in the demo
# system's profile: system.path/bin, plus system.path/share/omarchy/bin
# (the session PATH entry the module adds for the omarchy-* scripts).
# A missing binary only shows up at runtime as a Quickshell
# "Process failed to start" warning and a dead widget (xkbcli, upstream
# 2026-08-09, was one). Non-literal first elements
# (root.omarchyPath + "/bin/…", variables) are out of scope here; the
# ux test's exec-site count tripwire forces a review of those.
{
  self,
  system,
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  omarchyPkg = self.packages.${system}.omarchy;
  systemPath = self.nixosConfigurations.demo.config.system.path;
  # Programs the shell may start that the default system deliberately
  # does not ship. Each needs a reason; a stale entry (now resolvable,
  # or no longer referenced) fails the check so the list cannot rot.
  allowlist = {
    # Tailscale panel login plan (plugins/panels/tailscale/Model.js).
    # The CLI ships with the menu-managed `tailscale` feature
    # (services.tailscale.enable); the panel has nothing to control
    # without it.
    tailscale = "optional feature: services.tailscale (Install menu)";
  };
  allowlistFile = pkgs.writeText "qml-commands-allowlist" (
    lib.concatStringsSep "\n" (builtins.attrNames allowlist) + "\n"
  );
  extract = pkgs.writeText "extract-qml-commands.py" ''
    import pathlib, re, sys
    pat = re.compile(
        r"""(?:\bcommand\s*:|\bexecDetached\s*\()\s*\[\s*(["'])((?:(?!\1).)*)\1""",
        re.S,
    )
    root = pathlib.Path(sys.argv[1])
    for p in sorted(root.rglob("*")):
        if p.suffix not in (".qml", ".js") or not p.is_file():
            continue
        text = p.read_text()
        for m in pat.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            print(f"{m.group(2)}\t{p.relative_to(root)}:{line}")
  '';
in
pkgs.runCommand "omarchy-qml-commands-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -euo pipefail
  python3 ${extract} ${omarchyPkg}/share/omarchy/shell > sites.tsv
  cut -f1 sites.tsv | LC_ALL=C sort -u > commands.txt
  # Guard the extractor itself: a regex that silently matches nothing
  # would pass vacuously.
  n=$(wc -l < commands.txt)
  if [ "$n" -lt 20 ]; then
    echo "FAIL: only $n distinct shell commands extracted; extractor broken?" >&2
    cat sites.tsv >&2
    exit 1
  fi

  bad=0
  while read -r cmd; do
    if [ -x "${systemPath}/bin/$cmd" ] || [ -x "${systemPath}/share/omarchy/bin/$cmd" ]; then
      if grep -qxF "$cmd" ${allowlistFile}; then
        echo "FAIL: allowlisted '$cmd' now resolves on PATH; drop it from the allowlist" >&2
        bad=1
      fi
    elif ! grep -qxF "$cmd" ${allowlistFile}; then
      echo "FAIL: shell starts '$cmd', which is not on the desktop PATH:" >&2
      awk -F'\t' -v c="$cmd" '$1 == c { print "  " $2 }' sites.tsv >&2
      bad=1
    fi
  done < commands.txt
  while read -r allowed; do
    if ! grep -qxF "$allowed" commands.txt; then
      echo "FAIL: allowlisted '$allowed' is no longer started by the shell; drop it" >&2
      bad=1
    fi
  done < ${allowlistFile}
  [ "$bad" = 0 ] || exit 1
  echo "$n shell commands resolve"
  touch $out
''
