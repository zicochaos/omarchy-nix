# Aether — native Omarchy theming app.
#
# A Wails v2 application: a Go backend (github.com/wailsapp/wails/v2) with an
# embedded Svelte/Vite frontend. main.go does `//go:embed all:frontend/dist`,
# so the frontend must be built to frontend/dist before `go build`. The same
# binary also exposes a headless CLI (flags like `--status`, `--apply`) and an
# IPC subcommand mode for the running GUI instance.
#
# Build strategy (mirrors `wails build` without requiring the wails CLI):
#   1. `frontend` — a stdenvNoCC derivation compiles the Svelte/Vite app to a
#      dist tree. npm deps are prefetched as a FOD (fetchNpmDeps). We use
#      `npm install` (not `npm ci`) because the upstream package-lock.json
#      omits the @emnapi/* optional peer deps of @napi-rs/wasm-runtime (pulled
#      by the wasm32-wasi fallbacks of @tailwindcss/oxide and @rolldown/binding),
#      which `npm ci` rejects as out of sync. `npm install --offline` resolves
#      them from the prefetched cache and patches the lockfile in place.
#   2. buildGoModule compiles the Go binary against WebKitGTK 4.1 (the
#      `webkit2_41` wails build tag). postPatch drops the prebuilt dist into
#      frontend/dist so //go:embed resolves. (postPatch also runs in the
#      go-modules FOD harmlessly — `go mod vendor` ignores frontend/dist.)
#
# Runtime: a GTK/WebKit webview app. webkitgtk_4_1, gtk3, glib and friends are
# pulled transitively into the system profile by adding this package to
# environment.systemPackages — the omarchy module needs no extra runtimeDeps
# beyond that.
{
  lib,
  stdenvNoCC,
  buildGoModule,
  fetchFromGitHub,
  fetchNpmDeps,
  nodejs_22,
  pkg-config,
  wrapGAppsHook3,
  webkitgtk_4_1,
  gtk3,
  glib,
}:

let
  version = "4.28.0";

  src = fetchFromGitHub {
    owner = "bjarneo";
    repo = "aether";
    rev = "refs/tags/v${version}";
    hash = "sha256-IQH2bbuhrsoe71AH+NfklfBIRWw12VovYtzIIad6WrU=";
  };

  # fetcherVersion 2 fetches packuments, which npm install needs to resolve
  # the lockfile-missing @emnapi/* optional deps offline.
  npmDeps = fetchNpmDeps {
    inherit src;
    sourceRoot = "${src.name}/frontend";
    hash = "sha256-ysGl5k1fEavHxxz0Of3Aekdk7A2AtklxLJ3TVxM1XJA=";
    fetcherVersion = 2;
  };

  # Svelte/Vite frontend -> frontend/dist (consumed via //go:embed).
  frontend = stdenvNoCC.mkDerivation {
    pname = "aether-frontend";
    inherit version src;
    sourceRoot = "${src.name}/frontend";

    nativeBuildInputs = [ nodejs_22 ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export npm_config_cache="$PWD/npm-cache"
      cp -r "${npmDeps}"/. "$npm_config_cache"/
      chmod -R u+w "$npm_config_cache"
      npm install --offline --no-audit --no-fund --no-progress
      # npm-installed bin shims (and their symlink targets, e.g.
      # vite/bin/vite.js) use `#!/usr/bin/env node`, which does not exist in
      # the Nix sandbox. Rewrite the whole node_modules tree (matches
      # buildNpmPackage's npmConfigHook).
      patchShebangs node_modules
      npm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir "$out"
      cp -r dist/. "$out"/
      runHook postInstall
    '';
  };
in
buildGoModule (finalAttrs: {
  pname = "aether";
  inherit version src;

  vendorHash = "sha256-iIqJCRVgs1kg2nymuRO1FWdwbb8OhSAaQTCqaIdOPec=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
    glib
  ];

  # Wails v2 production desktop build. `production` selects the real app
  # runtime (without it wails ships a stub that errors "will not build without
  # the correct build tags"); `webkit2_41` links against WebKitGTK 4.1 (the
  # upstream Makefile picks this when webkit2gtk-4.0 is absent — our case).
  tags = [
    "production"
    "webkit2_41"
  ];

  # Inject the release version (cli.Version defaults to "dev" otherwise).
  ldflags = [ "-X aether/cli.Version=${version}" ];

  postPatch = ''
    rm -rf frontend/dist
    cp -r ${frontend} frontend/dist
  '';

  # GUI app — tests need a display/running instance; not meaningful sandboxed.
  doCheck = false;

  # Desktop integration (matches AUR package(): build/linux/aether.desktop +
  # icon.png). Source icon is 622x561; install under the closest standard
  # hicolor size so Icon=aether resolves from the applications entry.
  postInstall = ''
    install -Dm644 build/linux/aether.desktop \
      "$out/share/applications/aether.desktop"
    install -Dm644 icon.png \
      "$out/share/icons/hicolor/512x512/apps/aether.png"
  '';

  meta = {
    description = "Native Omarchy theming app — extract wallpaper colors and apply cohesive desktop themes";
    homepage = "https://github.com/bjarneo/aether";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "aether";
  };
})
