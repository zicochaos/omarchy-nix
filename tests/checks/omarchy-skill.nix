# The packaged agent skill is an intentional NixOS adaptation of
# upstream's Arch-only default. Keep the repository copy and the
# installed $OMARCHY_PATH copy byte-identical, and reject the
# dangerous Arch package-management guidance this port replaces.
{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
let
  sourceSkill = ../../skills/omarchy/SKILL.md;
  packagedSkill = "${
    self.packages.${system}.omarchy
  }/share/omarchy/default/agents/skills/omarchy/SKILL.md";
  upstreamSkill = "${inputs.omarchy-src}/default/agents/skills/omarchy/SKILL.md";
  parityManifest = ../../skills/omarchy/skill-parity.json;
in
pkgs.runCommand "omarchy-skill-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  cmp ${sourceSkill} ${packagedSkill}

  grep -Fq "name: omarchy" ${packagedSkill}
  grep -Fq "Omarchy on NixOS" ${packagedSkill}
  grep -Fq "\$OMARCHY_PATH" ${packagedSkill}
  grep -Fq "OMARCHY_NIX_FLAKE" ${packagedSkill}
  grep -Fq "omarchy-nix-search" ${packagedSkill}
  grep -Fq "omarchy-nix-add" ${packagedSkill}
  grep -Fq "omarchy-nix-remove" ${packagedSkill}
  grep -Fq "nixos-rebuild" ${packagedSkill}
  grep -Fq 'Do not use `pacman`, `yay`' ${packagedSkill}

  # Forbidden Arch guidance. Not `! grep`: bash -e ignores the status
  # of a `!`-negated command, so such a line can never fail the build.
  for forbidden in \
    "beautiful, modern, opinionated Arch Linux distribution" \
    "omarchy pkg aur add" \
    "/usr/share/omarchy"; do
    if grep -Fq -- "$forbidden" ${packagedSkill}; then
      echo "FAIL: packaged SKILL.md carries Arch-only guidance: $forbidden" >&2
      exit 1
    fi
  done

  # --- Semantic parity against the upstream skill ---------------
  # Every upstream h2-h4 (##+) heading and every Command Groups
  # table row must be classified in skill-parity.json (preserved /
  # adapted / omitted-with-reason) — and nothing stale may linger
  # in the manifest. A new upstream section or group fails this
  # check until it is classified.
  grep -E '^##{1,3} ' ${upstreamSkill} |
    sed -E 's/^##{1,3} //' | LC_ALL=C sort > upstream-sections.txt
  jq -r '.sections | keys[]' ${parityManifest} | LC_ALL=C sort > manifest-sections.txt
  if ! diff -u upstream-sections.txt manifest-sections.txt; then
    echo "FAIL: upstream skill sections diverge from skill-parity.json" >&2
    echo "(< unclassified upstream section, > stale manifest entry)" >&2
    exit 1
  fi

  grep -oE '^\| `omarchy [A-Za-z0-9_-]+` ' ${upstreamSkill} |
    sed -E 's/^\| `omarchy ([A-Za-z0-9_-]+)`.*/\1/' | LC_ALL=C sort > upstream-groups.txt
  jq -r '.commandGroups | keys[]' ${parityManifest} | LC_ALL=C sort > manifest-groups.txt
  if ! diff -u upstream-groups.txt manifest-groups.txt; then
    echo "FAIL: upstream command groups diverge from skill-parity.json" >&2
    echo "(< unclassified upstream group, > stale manifest entry)" >&2
    exit 1
  fi

  # Statuses are from the closed set; omitted REQUIRES a reason.
  jq -e '[.sections[], .commandGroups[] | .status] |
         all(. == "preserved" or . == "adapted" or . == "omitted")' \
    ${parityManifest} >/dev/null ||
    { echo "FAIL: invalid status in skill-parity.json" >&2; exit 1; }
  jq -e '[.sections[], .commandGroups[] | select(.status == "omitted")] |
         all(has("reason") and (.reason | length > 0))' \
    ${parityManifest} >/dev/null ||
    { echo "FAIL: omitted entry without a reason in skill-parity.json" >&2; exit 1; }

  # Anchors for the adapted coverage the manifest claims.
  grep -Fq "## Privilege Escalation" ${packagedSkill}
  grep -Fq "/run/wrappers/bin/sudo" ${packagedSkill}
  grep -Fq "### Other Configs" ${packagedSkill}
  grep -Fq "omarchy font set" ${packagedSkill}
  grep -Fq "omarchy system lock" ${packagedSkill}
  grep -Fq "## Out of Scope" ${packagedSkill}
  grep -Fq "## Example Requests" ${packagedSkill}
  grep -Fq "nix-add" ${packagedSkill}

  # Manifest-driven anchors: every entry carrying an 'anchor'
  # string must have that string present in our SKILL.md — this
  # proves classified content (esp. preserved sections/groups) is
  # actually there, not just classified.
  jq -r '[.sections[], .commandGroups[] | select(has("anchor")) | .anchor] | .[]' \
    ${parityManifest} > parity-anchors.txt
  # An empty anchor list would make the loop below pass vacuously.
  [ -s parity-anchors.txt ] ||
    { echo "FAIL: skill-parity.json yielded no anchors" >&2; exit 1; }
  while IFS= read -r anchor; do
    grep -Fq -- "$anchor" ${packagedSkill} ||
      { echo "FAIL: parity anchor missing from SKILL.md: $anchor" >&2; exit 1; }
  done < parity-anchors.txt

  touch "$out"
''
