# quickshell 0.3.2 pin.
#
# Stable nixpkgs (nixos-26.05) carries quickshell 0.3.0. 0.3.1 fixed the
# plugin-reload side effect measured in this port; 33783b1's shell needs
# 0.3.2 (the QML gained the OmarchyLoadPatch pragma, which 0.3.1 logs as
# unrecognized — the menu plugin then never registers and every
# `omarchy menu summon` answers "unknown" while exiting 0, measured in
# checks.omarchy-ux). After `omarchy plugin
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
# relies on. 0.3.1/0.3.2 also carry crash fixes relevant to a desktop
# (session lock on sleep/wake/DPMS/unlock, wifi disappearance, FileView
# updates, IPC children of a relaunched process).
#
# The recipe is identical between the two versions in the pinned nixpkgs
# (diff: version + src hash), so this overrides the recipe instead of
# vendoring it. If a future nixpkgs recipe diverges from 0.3.x, the build
# fails loudly here. When the nixpkgs pin carries 0.3.2 or newer, drop this
# file, the flake's packages entry, the wrapper injection and
# checks.omarchy-quickshell-version; omarchy.quickshellPackage stays as the
# null -> pkgs.quickshell escape hatch. The ux test asserts the post-reload
# OSD behaviour, so the bump is guarded either way.
{
  quickshell,
  fetchFromGitea,
}:
quickshell.overrideAttrs (old: {
  version = "0.3.2";
  src = fetchFromGitea {
    domain = "git.outfoxxed.me";
    owner = "quickshell";
    repo = "quickshell";
    tag = "v0.3.2";
    hash = "sha256-lPbqsyAD5ZoGFMZ1eqAlTULfeP5Nwhy+XvOowF7BE+E=";
  };
  # Upstream builds quickshell with load_qtquick_611.patch (omacom/
  # omarchy-pkgs pkgbuilds/quickshell): it adds the `OmarchyLoadPatch`
  # pragma the 33783b1 shell functionally requires (without it the menu
  # panel never opens — the localized-label loading rides on the patch's
  # file interception; measured in checks.omarchy-ux). Keep in sync with
  # upstream's PKGBUILD on every quickshell bump.
  #
  # intercept-rescan-fix.patch is this port's addition: upstream's patch
  # calls scanner.scanDir() synchronously from the QML engine thread on
  # every intercepted URL, which deadlocks the engine during the shell's
  # plugin reload on this pin's Qt (6.11.2) — the shell goes silent after
  # "Local plugin changed, reloading" and the lazily loaded panels (menu
  # included) never come back. Dropping the call keeps the interception
  # table the initial scan and the watcher maintain. Drop this patch when
  # upstream's pkgbuild carries an equivalent fix or the pin's Qt moves to
  # 6.12 (upstream's tested combination).
  patches = (old.patches or [ ]) ++ [
    ./quickshell/load_qtquick_611.patch
    ./quickshell/intercept-rescan-fix.patch
  ];
})
