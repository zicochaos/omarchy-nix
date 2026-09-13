# quickshell 0.3.1 pin.
#
# Stable nixpkgs (nixos-26.05) carries quickshell 0.3.0. 0.3.1 fixes the
# plugin-reload side effect measured in this port. After `omarchy plugin
# clone` the shell reloads every plugin; on 0.3.0 that reload logged a
# duplicate-handler warning for the OSD target ("Handler was registered but
# will not be used because another handler is registered for target osd"),
# the stale handler belonged to the destroyed OSD instance, and the FIRST
# `omarchy osd` call after the reload rendered nothing (all 5 preserved probe
# runs) — `omarchy osd` kept exiting 0 regardless. Some runs recovered on a
# later call; others stayed dead for 30 s+ (the ux volume-OSD section timed
# out that way twice). On 0.3.1 the first call after the reload renders in
# every run (6 preserved runs, CI included) and no osd-target warning
# appears. Measured with
# tests/probe-quickshell-reload.nix (same probe, only the package swapped:
# baseline OSD works on both, reload confirmed in both shell logs).
#
# Note the reload still logs duplicate-handler warnings for the bar-widget
# targets on 0.3.1 (weather, clock, indicators, system-update and the clone
# itself) — upstream's broader stale-handler class
# (omacom/omarchy#9533/#10746); they do not affect the OSD path this port
# relies on. 0.3.1 also carries crash fixes relevant to a desktop (session
# lock on sleep/wake/DPMS/unlock, wifi disappearance, FileView updates, IPC
# children of a relaunched process).
#
# The recipe is identical between the two versions in the pinned nixpkgs
# (diff: version + src hash), so this overrides the recipe instead of
# vendoring it. If a future nixpkgs recipe diverges from 0.3.x, the build
# fails loudly here. When the nixpkgs pin carries 0.3.1 or newer, drop this
# file, the flake's packages entry, the wrapper injection and
# checks.omarchy-quickshell-version; omarchy.quickshellPackage stays as the
# null -> pkgs.quickshell escape hatch. The ux test asserts the post-reload
# OSD behaviour, so the bump is guarded either way.
{
  quickshell,
  fetchFromGitea,
}:
quickshell.overrideAttrs (old: {
  version = "0.3.1";
  src = fetchFromGitea {
    domain = "git.outfoxxed.me";
    owner = "quickshell";
    repo = "quickshell";
    tag = "v0.3.1";
    hash = "sha256-CLX2Zp5i5BuLbOxNOkwRd9YY84IOrACNxBV79o9/F9Y=";
  };
})
