# Pure serializers/validators for omarchy.* option values.
#
# Two output formats are generated from user-controlled option strings:
#   - ~/.config/hypr/monitors.lua   (Lua, loaded by Hyprland)
#   - /etc/environment.d/50-omarchy.conf (systemd environment.d(5))
# Naive string interpolation into either is a code-injection / key-injection
# vector (a quote or newline in a monitor name breaks `luac -p`; a newline in
# full_name can forge a second env assignment). All serialization goes through
# the escaping helpers here; validation throws at evaluation time so a bad
# value fails `nixos-rebuild` before anything is written.
{ lib }:
let
  inherit (lib.strings) trim;

  # --- Lua ---------------------------------------------------------------
  # Escape a string for inclusion inside a Lua double-quoted literal.
  # builtins.replaceStrings is single-pass (it scans the source once, so
  # already-emitted backslashes are never re-matched) — order is irrelevant.
  luaEscape =
    builtins.replaceStrings
      [
        "\\"
        "\""
        "\n"
        "\r"
        "	"
      ]
      [
        "\\\\"
        "\\\""
        "\\n"
        "\\r"
        "\\t"
      ];

  # A complete Lua double-quoted string literal for s.
  luaStr = s: ''"${luaEscape s}"'';

  isNumericScale = s: builtins.match "[0-9]+(\\.[0-9]+)?" s != null;

  # Parse one Hyprland monitor directive ("output, mode, position, scale,
  # [transform]") into validated fields. Empty fields become null (Hyprland
  # then applies its defaults). Throws on anything outside the supported
  # grammar — better a clear eval error than a broken monitors.lua.
  #
  # Returns: { output, mode, position, scale, transform } where scale is
  #   null | { type = "number"; value = "1.5"; } | { type = "string"; value = "auto"; }
  # and transform is null | "0".."7" (emitted unquoted — Hyprland expects a
  # number from the 0-7 rotation domain).
  parseMonitor =
    entry:
    let
      fields = map trim (lib.splitString "," entry);
      n = builtins.length fields;
      f = i: if i < n && builtins.elemAt fields i != "" then builtins.elemAt fields i else null;
      output = f 0;
      mode = f 1;
      position = f 2;
      scaleStr = f 3;
      transform = f 4;
      # WIDTHxHEIGHT or WIDTHxHEIGHT@RATE (RATE may be fractional, e.g.
      # 59.94), or a Hyprland mode keyword (preferred/highres/highrr — the
      # same set the catch-all and upstream tooling use).
      isMode =
        s:
        builtins.match "[0-9]+x[0-9]+(@[0-9]+(\\.[0-9]+)?)?" s != null
        || builtins.elem s [
          "preferred"
          "highres"
          "highrr"
        ];
      # Absolute XxY (optional leading - for multi-monitor layouts) or the
      # auto / auto-* keywords Hyprland accepts (and that the catch-all uses).
      isPosition =
        s: builtins.match "-?[0-9]+x-?[0-9]+" s != null || builtins.match "auto(-[A-Za-z]+)?" s != null;
      scale =
        if scaleStr == null then
          null
        else if isNumericScale scaleStr then
          {
            type = "number";
            value = scaleStr;
          }
        else if scaleStr == "auto" then
          {
            type = "string";
            value = "auto";
          }
        else
          throw "omarchy.monitors: unsupported scale '${scaleStr}' in '${entry}' (want a number or 'auto')";
      checkedTransform =
        if transform == null then
          null
        else if builtins.match "[0-7]" transform != null then
          transform
        else
          throw "omarchy.monitors: unsupported transform '${transform}' in '${entry}' (want 0-7)";
      checkedMode =
        if mode == null then
          null
        else if isMode mode then
          mode
        else
          throw "omarchy.monitors: unsupported mode '${mode}' in '${entry}' (want WIDTHxHEIGHT or WIDTHxHEIGHT@RATE, e.g. 2560x1440@144, or preferred/highres/highrr)";
      checkedPosition =
        if position == null then
          null
        else if isPosition position then
          position
        else
          throw "omarchy.monitors: unsupported position '${position}' in '${entry}' (want XxY integers, e.g. 0x0, or 'auto'/'auto-right'/...)";
    in
    if n > 5 then
      throw "omarchy.monitors: entry has ${toString n} comma-separated fields (max 5: output, mode, position, scale, transform): '${entry}'"
    else if output == null then
      throw "omarchy.monitors: empty output name (first field) in '${entry}'"
    else
      {
        inherit output scale;
        mode = checkedMode;
        position = checkedPosition;
        transform = checkedTransform;
      };

  # One validated hl.monitor({}) call.
  monitorToLua =
    entry:
    let
      m = parseMonitor entry;
      scaleLua =
        if m.scale == null then
          null
        else if m.scale.type == "number" then
          m.scale.value
        else
          luaStr m.scale.value;
      parts = [
        "output = ${luaStr m.output}"
      ]
      ++ (lib.optional (m.mode != null) "mode = ${luaStr m.mode}")
      ++ (lib.optional (m.position != null) "position = ${luaStr m.position}")
      ++ (lib.optional (scaleLua != null) "scale = ${scaleLua}")
      ++ (lib.optional (m.transform != null) "transform = ${m.transform}");
    in
    "hl.monitor({ ${lib.concatStringsSep ", " parts} })";

  # Full text of ~/.config/hypr/monitors.lua. The catch-all (output = "")
  # and the omarchy_gdk_scale / omarchy_monitor_scale locals MUST keep their
  # exact line shapes: upstream runtime tooling
  # (omarchy-hyprland-monitor-scaling) greps for them to persist
  # user-initiated scaling changes back to this file.
  monitorsLuaText =
    { scale, monitors }:
    if
      !builtins.elem scale [
        1
        2
      ]
    then
      throw "omarchy.scale must be 1 or 2 (got ${toString scale})"
    else
      let
        monitorScale = if scale == 1 then "auto" else "1.2";
        monitorLines = map monitorToLua monitors;
      in
      ''
        -- See https://wiki.hypr.land/Configuring/Basics/Monitors/
        -- List current monitors and supported resolutions with: hyprctl monitors all
        -- Generated by omarchy-nix from omarchy.scale (${toString scale}) and
        -- omarchy.monitors (${toString (builtins.length monitors)} entries).

        local omarchy_gdk_scale = ${toString scale}
        local omarchy_monitor_scale = "${monitorScale}"

        hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
        hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

        ${lib.optionalString (monitorLines != [ ]) ''
          -- Per-monitor configuration from omarchy.monitors.
          ${lib.concatStringsSep "\n" monitorLines}
        ''}
      '';

  # --- systemd environment.d(5) -------------------------------------------
  # Escape rules below are empirically verified against systemd 260's
  # 30-systemd-environment-d-generator:
  #   - inside double quotes the parser unescapes ONLY \\ and \"; \n/\t are
  #     NOT escapes there (a literal backslash + letter survives)
  #   - $$ emits a literal $; bare $VAR/${VAR} expands from the manager's
  #     environment (an unset variable expands to empty) — so $ must escape
  #   - an empty assignment (quoted "" or bare) is rejected by the generator
  #     ("invalid syntax, ignoring") — environment.d simply cannot deliver
  #     an empty value, so envdLines OMITS empty values
  #   - a raw newline inside quotes is folded into the value without forging
  #     a new key, but the generator's own serializer re-emits it as \n —
  #     which the parser does not read back (asymmetric). Raw CR/LF is
  #     therefore rejected at the option-type level (strMatching in
  #     config.nix), never escaped here.
  envdEscape =
    builtins.replaceStrings
      [
        "\\"
        "\""
        "$"
      ]
      [
        "\\\\"
        "\\\""
        "$$"
      ];

  # One NAME="value" line. Throws on an empty value — use envdLines, which
  # filters empties out before they reach here.
  envdLine =
    name: value:
    if value == "" then
      throw "omarchy-formats: environment.d cannot express an empty value for ${name}"
    else
      ''${name}="${envdEscape value}"'';

  # Serialize an attrset of env vars to environment.d syntax, one line per
  # key, skipping empty values.
  envdLines =
    attrs:
    lib.concatStringsSep "\n" (lib.mapAttrsToList envdLine (lib.filterAttrs (_: v: v != "") attrs));
in
{
  inherit
    luaEscape
    luaStr
    parseMonitor
    monitorToLua
    monitorsLuaText
    envdEscape
    envdLine
    envdLines
    ;
}
