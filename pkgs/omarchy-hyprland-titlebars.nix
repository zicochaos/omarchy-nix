# omarchy-hyprland-titlebars — Hyprland plugin giving Omarchy's floating
# workspace mode its window titlebars (upstream base package since 33783b1;
# fork of hyprwm's hyprbars, registered under Hyprland's `hyprbars` name so
# the omarchy Lua config's hl.plugin.hyprbars interface keeps working).
#
# MUST be built against the same Hyprland the desktop runs (plugin ABI):
# the flake calls this with hyprland = the `hyprland` flake input's package
# and the nixpkgs of that input, so headers, toolchain and linked libs line
# up with the compositor. The vendored workspace-modes.lua loads the .so
# from a path substituted at omarchy-package build time.
#
# The plugin exchanges C++ objects with the Hyprland host and links only
# system libraries (libdrm/libinput/udev/pixman/wayland-server/xkbcommon —
# all in hyprland.buildInputs); the `hyprland` pkg-config module supplies
# the headers.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  hyprland,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "omarchy-hyprland-titlebars";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-hyprland-titlebars";
    rev = "v${finalAttrs.version}";
    hash = "sha256-K7IHVqS0HHkJM/ytq1YF+seWB4tEs80eFJK8TAHbqbQ=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  # hyprland first: its dev output provides hyprland.pc; its buildInputs
  # cover every pkg_check_modules dependency of CMakeLists.txt.
  buildInputs = [ hyprland ] ++ hyprland.buildInputs;

  meta = {
    description = "Titlebars for Omarchy's floating workspaces (Hyprland plugin)";
    homepage = "https://github.com/omacom/omarchy-hyprland-titlebars";
    license = with lib.licenses; [
      bsd3 # hyprbars origin
      mit # Omarchy's changes
    ];
    platforms = lib.platforms.linux;
  };
})
