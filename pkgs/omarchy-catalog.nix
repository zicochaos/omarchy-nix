# Catalog of menu Install/Remove entries mapped to nixpkgs attributes or
# module features — the NixOS-native analogue of upstream's Arch package
# choices. Single source of truth for:
#   - omarchy-nix-add / omarchy-nix-remove (what they write into
#     omarchy-packages.json),
#   - omarchy-pkg-present (menu `when:` guards: JSON membership or binary
#     probe on `binaries`),
#   - the NixOS module (unfree whitelist + insecure permit via
#     `unfreeNames` / `insecureNames` + features.*.unfreeNames).
# Attribute names and unfree/insecure lists verified against this flake's
# nixos-26.05 pin (2026-07-28; the install.ai.* agent entries 2026-08-05): each entry's pkgs forced via .drvPath under
# allowUnfreePredicate = [ "obsidian" ] ++ unfreeNames and
# permittedInsecurePackages = insecureNames. getName may differ from the
# attr name (e.g. sublime4 → sublimetext4); wrappers may pull extra unfree
# deps (steam → steam-unwrapped; dropbox → firefox-bin{,-unwrapped}; lutris
# → steam + steam-unwrapped).
{
  # Actionable menu entries (install.* ids). arch = the Arch package name
  # upstream `when:` guards pass to omarchy-pkg-present. pkgs XOR feature per
  # entry. binaries = probe list for pkg-present. configSeed = upstream
  # default config dir copied to ~/.config after install (parity with
  # omarchy-install-terminal).
  #
  # unfreeNames = literal lib.getName strings the consumer path must
  # whitelist (not attr names). insecureNames = full name-version strings
  # for nixpkgs.config.permittedInsecurePackages (only when selected).
  entries = {
    # --- Browsers ---
    "install.browser.chrome" = {
      arch = "google-chrome";
      pkgs = [ "google-chrome" ];
      binaries = [ "google-chrome-stable" ];
      unfreeNames = [ "google-chrome" ];
    };
    "install.browser.edge" = {
      arch = "microsoft-edge-stable-bin";
      pkgs = [ "microsoft-edge" ];
      binaries = [ "microsoft-edge" ];
      unfreeNames = [ "microsoft-edge" ];
    };
    "install.browser.brave" = {
      arch = "brave-bin";
      pkgs = [ "brave" ];
      binaries = [ "brave" ];
    };
    "install.browser.firefox" = {
      arch = "firefox";
      pkgs = [ "firefox" ];
      binaries = [ "firefox" ];
    };
    # --- Services ---
    "install.service.1password" = {
      arch = "1password";
      feature = "onepassword";
      binaries = [ "1password" ];
    };
    "install.service.dropbox" = {
      arch = "dropbox";
      pkgs = [ "dropbox" ];
      binaries = [ "dropbox" ];
      # dropbox.desktop Exec uses firefox-bin for OAuth; both the wrapper and
      # the unwrapped firefox are unfree under the firefox license.
      unfreeNames = [
        "dropbox"
        "firefox-bin"
        "firefox-bin-unwrapped"
      ];
    };
    "install.service.spotify" = {
      arch = "spotify";
      pkgs = [ "spotify" ];
      binaries = [ "spotify" ];
      unfreeNames = [ "spotify" ];
    };
    "install.service.signal" = {
      arch = "signal-desktop";
      pkgs = [ "signal-desktop" ];
      binaries = [ "signal-desktop" ];
    };
    "install.service.tailscale" = {
      arch = "tailscale";
      feature = "tailscale";
      binaries = [ "tailscale" ];
    };
    "install.service.bitwarden" = {
      arch = "bitwarden";
      pkgs = [ "bitwarden-desktop" ];
      binaries = [ "bitwarden" ];
      # bitwarden-desktop itself is free (GPL3) on this pin; its electron
      # runtime is marked insecure — permit only when selected.
      insecureNames = [ "electron-39.8.10" ];
    };
    # --- Editors ---
    "install.editor.vscode" = {
      arch = "visual-studio-code-bin";
      pkgs = [ "vscode" ];
      binaries = [ "code" ];
      unfreeNames = [ "vscode" ];
    };
    "install.editor.cursor" = {
      arch = "cursor-bin";
      pkgs = [ "code-cursor" ];
      binaries = [ "cursor" ];
      # attr code-cursor, getName = "cursor"
      unfreeNames = [ "cursor" ];
    };
    "install.editor.zed" = {
      arch = "zed";
      pkgs = [ "zed-editor" ];
      binaries = [ "zeditor" ];
    };
    "install.editor.sublime" = {
      arch = "sublime-text-4";
      pkgs = [ "sublime4" ];
      binaries = [ "subl" ];
      # attr sublime4, getName = "sublimetext4"; pulls openssl 1.1.1w (insecure).
      unfreeNames = [ "sublimetext4" ];
      insecureNames = [ "openssl-1.1.1w" ];
      # Newer nixpkgs (≥26.11) marks sublimetext4 broken via the problems
      # mechanism — scope the opt-in to when the entry is selected.
      problemHandlers = [ "sublimetext4.broken" ];
    };
    "install.editor.helix" = {
      arch = "helix";
      pkgs = [ "helix" ];
      binaries = [ "hx" ];
    };
    "install.editor.vim" = {
      arch = "vim";
      pkgs = [ "vim" ];
      binaries = [ "vim" ];
    };
    "install.editor.emacs" = {
      arch = "omarchy-emacs";
      pkgs = [ "emacs" ];
      binaries = [ "emacs" ];
    };
    # --- Terminals ---
    "install.terminal.alacritty" = {
      arch = "alacritty";
      pkgs = [ "alacritty" ];
      binaries = [ "alacritty" ];
      configSeed = "alacritty";
    };
    "install.terminal.foot" = {
      arch = "foot";
      pkgs = [ "foot" ];
      binaries = [ "foot" ];
    };
    "install.terminal.ghostty" = {
      arch = "ghostty";
      pkgs = [ "ghostty" ];
      binaries = [ "ghostty" ];
    };
    "install.terminal.kitty" = {
      arch = "kitty";
      pkgs = [ "kitty" ];
      binaries = [ "kitty" ];
    };
    # --- AI ---
    "install.ai.lm-studio" = {
      arch = "lmstudio-bin";
      pkgs = [ "lmstudio" ];
      binaries = [ "lm-studio" ];
      unfreeNames = [ "lmstudio" ];
    };
    "install.ai.ollama" = {
      arch = "ollama";
      feature = "ollama";
      binaries = [ "ollama" ];
    };
    # v4.0.3: OpenClaw is both an Install > AI app and a default-agent
    # choice upstream (Arch installs it via its own pacman package + CLI
    # installer). The nixpkgs package is MIT but currently flagged insecure
    # (2026.5.7) — the permit is entry-scoped, like bitwarden's electron.
    "install.ai.openclaw" = {
      arch = "openclaw";
      pkgs = [ "openclaw" ];
      binaries = [ "openclaw" ];
      insecureNames = [ "openclaw-2026.5.7" ];
    };
    "install.ai.crush" = {
      arch = "crush-bin";
      pkgs = [ "crush" ];
      binaries = [ "crush" ];
      unfreeNames = [ "crush" ];
    };
    # Claude Desktop: Anthropic's own Debian .deb, unpacked by the in-repo
    # derivation (pkgs/claude-desktop.nix) — nixpkgs does not carry the
    # attr, so the managed-packages block resolves it through
    # omarchy.ownedPackages (flake-injected); switch `pkgs` to the nixpkgs
    # attr once NixOS/nixpkgs#537215 reaches the pin. The `install.ai.claude`
    # id stays owned by the Claude Code agent entry below.
    "install.ai.claude-desktop" = {
      arch = "claude-desktop";
      pkgs = [ "claude-desktop" ];
      binaries = [ "claude-desktop" ];
      unfreeNames = [ "claude-desktop" ];
    };
    # T3 Code (t3.codes, MIT): nixpkgs carries it on the pin (t3code,
    # built from source — the upstream Arch package is an AppImage repack,
    # hence the arch name t3code-bin with the t3code-desktop binary here).
    # The pin's 0.0.28 bundles electron 40.10.5, flagged insecure (EOL) —
    # the bitwarden-electron pattern: entry-scoped permit, applied only
    # when the entry is selected.
    "install.ai.t3-code" = {
      arch = "t3code-bin";
      pkgs = [ "t3code" ];
      binaries = [ "t3code-desktop" ];
      insecureNames = [ "electron-40.10.5" ];
    };
    # Oh My Pi (omp): can1357/oh-my-pi, MIT — release binary packaged
    # in-repo (pkgs/omp.nix; the mise model is rejected here). Resolved
    # through omarchy.ownedPackages.
    "install.ai.omp" = {
      arch = "omp";
      pkgs = [ "omp" ];
      binaries = [ "omp" ];
    };
    # Hermes Agent (Nous Research, MIT) — the `hermes` default-agent CLI,
    # consumed from the project's own flake input via omarchy.ownedPackages.
    # Upstream's install.ai.hermes id is the Hermes Desktop app pair
    # (dropped — not packaged here); this id is the agent.
    "install.ai.hermes" = {
      arch = "hermes";
      pkgs = [ "hermes-agent" ];
      binaries = [ "hermes" ];
    };
    # --- Default coding agents (Setup > Defaults > Agent) ---
    # Upstream lazy-installs these with `mise use -g`; here they are catalog
    # entries, installed declaratively and then selectable as the default.
    "install.ai.claude" = {
      arch = "claude-code";
      pkgs = [ "claude-code" ];
      binaries = [ "claude" ];
      unfreeNames = [ "claude-code" ];
    };
    "install.ai.codex" = {
      arch = "codex-cli";
      pkgs = [ "codex" ];
      binaries = [ "codex" ];
    };
    "install.ai.copilot" = {
      arch = "github-copilot-cli";
      pkgs = [ "github-copilot-cli" ];
      binaries = [ "copilot" ];
      unfreeNames = [ "github-copilot-cli" ];
    };
    # v4.0.1: upstream replaced Gemini with Antigravity (agy); the 2f5a153c27
    # pin has no antigravity-cli attr, so there is no agy entry either — the
    # setup.default.agent.agy menu line is dropped at package time (like omp).
    "install.ai.grok" = {
      arch = "grok-cli";
      pkgs = [ "grok-cli" ];
      binaries = [ "grok" ];
    };
    "install.ai.opencode" = {
      arch = "opencode";
      pkgs = [ "opencode" ];
      binaries = [ "opencode" ];
    };
    "install.ai.pi" = {
      arch = "pi-coding-agent";
      pkgs = [ "pi-coding-agent" ];
      binaries = [ "pi" ];
    };
    # --- Gaming ---
    "install.gaming.steam" = {
      arch = "steam";
      feature = "steam";
      binaries = [ "steam" ];
    };
    "install.gaming.retroarch" = {
      arch = "retroarch";
      pkgs = [ "retroarch" ];
      binaries = [ "retroarch" ];
    };
    "install.gaming.minecraft" = {
      # Upstream ships the official launcher (AUR minecraft-launcher); it was
      # removed from nixpkgs, so the opinionated NixOS mapping is Prism.
      arch = "minecraft-launcher";
      pkgs = [ "prismlauncher" ];
      binaries = [ "prismlauncher" ];
    };
    "install.gaming.heroic" = {
      arch = "heroic-games-launcher-bin";
      pkgs = [ "heroic" ];
      binaries = [ "heroic" ];
    };
    "install.gaming.lutris" = {
      arch = "lutris";
      pkgs = [ "lutris" ];
      binaries = [ "lutris" ];
      # lutris itself is free but its closure pulls steam + steam-unwrapped.
      unfreeNames = [
        "steam"
        "steam-unwrapped"
      ];
    };
    "install.gaming.xbox-controllers" = {
      # No userspace package: the feature block enables the xpadneo kernel
      # module + bluetooth (the Arch modprobe script is quarantined).
      arch = "xpadneo-dkms";
      feature = "xpadneo";
      binaries = [ ];
    };
    # --- Development (upstream: mise dev envs) ---
    "install.development.rails" = {
      arch = "ruby";
      pkgs = [ "ruby" ];
      binaries = [ "ruby" ];
    };
    "install.development.go" = {
      arch = "go";
      pkgs = [ "go" ];
      binaries = [ "go" ];
    };
    "install.development.python" = {
      arch = "python";
      pkgs = [ "python3" ];
      binaries = [ "python3" ];
    };
    "install.development.zig" = {
      arch = "zig";
      pkgs = [ "zig" ];
      binaries = [ "zig" ];
    };
    "install.development.rust" = {
      arch = "rust";
      pkgs = [
        "rustc"
        "cargo"
      ];
      binaries = [
        "cargo"
        "rustc"
      ];
    };
    "install.development.java" = {
      arch = "java";
      pkgs = [ "jdk" ];
      binaries = [ "java" ];
    };
    "install.development.dotnet" = {
      arch = "dotnet";
      pkgs = [ "dotnet-sdk_9" ];
      binaries = [ "dotnet" ];
    };
    "install.development.ocaml" = {
      arch = "ocaml";
      pkgs = [ "ocaml" ];
      binaries = [ "ocaml" ];
    };
    "install.development.clojure" = {
      arch = "clojure";
      pkgs = [ "clojure" ];
      binaries = [ "clojure" ];
    };
    "install.development.scala" = {
      arch = "scala";
      pkgs = [ "scala" ];
      binaries = [ "scala" ];
    };
    "install.development.javascript.node" = {
      arch = "node";
      pkgs = [ "nodejs_22" ];
      binaries = [ "node" ];
    };
    "install.development.javascript.bun" = {
      arch = "bun";
      pkgs = [ "bun" ];
      binaries = [ "bun" ];
    };
    "install.development.javascript.deno" = {
      arch = "deno";
      pkgs = [ "deno" ];
      binaries = [ "deno" ];
    };
    "install.development.php.php" = {
      arch = "php";
      pkgs = [ "php" ];
      binaries = [ "php" ];
    };
    "install.development.elixir.elixir" = {
      arch = "elixir";
      pkgs = [ "elixir" ];
      binaries = [ "elixir" ];
    };
  };

  # Feature names usable in omarchy-packages.json "features".
  # unfreePkgs = real nixpkgs attributes the feature block pulls (for the
  # attr-existence check; NOT throw-aliases). unfreeNames = literal
  # lib.getName strings the (B0) whitelist must allow when the feature is
  # selected (may differ from attr names, e.g. _1password-gui → 1password).
  features = {
    steam = {
      unfreePkgs = [
        "steam"
        "steam-unwrapped"
      ];
      unfreeNames = [
        "steam"
        "steam-unwrapped"
      ];
    };
    tailscale = {
      unfreePkgs = [ ];
      unfreeNames = [ ];
    };
    onepassword = {
      # `_1password` is a removed throw-alias; the real attrs are -cli/-gui.
      unfreePkgs = [
        "_1password-cli"
        "_1password-gui"
      ];
      unfreeNames = [
        "1password-cli"
        "1password"
      ];
    };
    ollama = {
      unfreePkgs = [ ];
      unfreeNames = [ ];
    };
    xpadneo = {
      unfreePkgs = [ ];
      unfreeNames = [ ];
    };
  };

  # Arch names that appear in menu guards but only need a binary probe (the
  # package is already shipped by the module, so the guard just hides/shows
  # the entry). Keyed by the arch name passed to omarchy-pkg-present.
  aliases = {
    "voxtype-bin".binaries = [ "voxtype" ];
  };
}
