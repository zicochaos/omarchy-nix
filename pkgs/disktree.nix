# Upstream's graphical disk-space treemap, shipped as the same release binary
# as omacom/omarchy-pkgs' disktree-bin. No matching package exists in our pin.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  libxcb,
  libxkbcommon,
  wayland,
  libglvnd,
  vulkan-loader,
  glib,
  git,
  trash-cli,
  xdg-utils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "disktree";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/tobi/disktree/releases/download/v${finalAttrs.version}/disktree-${finalAttrs.version}-x86_64-linux.tar.gz";
    hash = "sha256-fnWvoig8i0+SkNUurb/ADZ8UwTrtLSJMzfD3gm/MBbI=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    libxcb
    libxkbcommon
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 disktree "$out/bin/disktree"
    install -Dm644 disktree.svg "$out/share/icons/hicolor/scalable/apps/disktree.svg"
    install -Dm644 LICENSE "$out/share/licenses/disktree/LICENSE"
    install -Dm644 README.md "$out/share/doc/disktree/README.md"
    mkdir -p "$out/share/applications"
    substitute disktree.desktop.in "$out/share/applications/disktree.desktop" \
      --replace-fail '@BINDIR@' "$out/bin" \
      --replace-fail '@VERSION@' '${finalAttrs.version}'
    runHook postInstall
  '';

  # winit/wgpu loads the compositor and graphics libraries dynamically.
  # Supply deletion-to-trash, directory-opening and Git inspection helpers.
  postFixup = ''
    wrapProgram "$out/bin/disktree" \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          wayland
          libglvnd
          vulkan-loader
        ]
      } \
      --prefix PATH : ${
        lib.makeBinPath [
          glib
          git
          trash-cli
          xdg-utils
        ]
      }
  '';

  meta = {
    description = "Graphical disk-space treemap with reviewed cleanup selections";
    homepage = "https://github.com/tobi/disktree";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "disktree";
  };
})
