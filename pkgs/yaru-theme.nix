# Yaru icon + GTK themes without gtk-engine-murrine.
#
# nixpkgs removed `yaru-theme` on 2026-07-22 because it propagated
# `gtk-engine-murrine` (GTK 2, unmaintained). Omarchy needs the Yaru-* icon
# themes (every stock theme's icons.theme points at one; gnome-theme.sh sets
# Yaru-blue on first run). Accent icon generation requires the gtk meson
# component, but the murrine *runtime* engine is not required for icons or
# modern GTK3/4 theming.
#
# Vendored here so consumers on nixpkgs ≥ that removal still get Yaru icons
# when evaluating the omarchy module against their own `pkgs`.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  sassc,
  pkg-config,
  glib,
  ninja,
  python3,
  gtk3,
  gnome-themes-extra,
  humanity-icon-theme,
  hicolor-icon-theme,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "yaru-theme";
  version = "25.10.3";

  src = fetchFromGitHub {
    owner = "ubuntu";
    repo = "yaru";
    rev = finalAttrs.version;
    hash = "sha256-3cSVPObfmr62S6yTD2c8AO3s7lxb9KFVuYSydTIJ1jE=";
  };

  nativeBuildInputs = [
    meson
    sassc
    pkg-config
    glib
    ninja
    python3
  ];

  buildInputs = [
    gtk3
    gnome-themes-extra
  ];

  propagatedBuildInputs = [
    humanity-icon-theme
    hicolor-icon-theme
  ];

  # No gtk-engine-murrine: removed from nixpkgs; not needed for icon themes.

  dontDropIconThemeCache = true;

  postPatch = "patchShebangs .";

  # Skip components Omarchy does not use (GNOME Shell, sounds, sessions).
  # Keep gtk=true: accent icon themes (Yaru-blue, …) are generated from GTK
  # color definitions and are skipped when gtk is disabled.
  mesonFlags = [
    "-Dgnome-shell=false"
    "-Dgtksourceview=false"
    "-Dmetacity=false"
    "-Dsounds=false"
    "-Dsessions=false"
  ];

  meta = {
    description = "Ubuntu Yaru theme (icons + GTK, no gtk-engine-murrine)";
    homepage = "https://github.com/ubuntu/yaru";
    license = with lib.licenses; [
      cc-by-sa-40
      gpl3Plus
      lgpl21Only
      lgpl3Only
    ];
    platforms = lib.platforms.linux;
  };
})
