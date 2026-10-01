# Option-value validation + safe serialization. Three
# layers:
#   1. negative eval cases — rejected values must throw at
#      evaluation time while a valid value of the same option (the
#      positive control) evaluates (forced via the negativeCases env
#      var, which is evaluated when the derivation is instantiated)
#   2. monitors.lua — luac -p syntax check + a Lua harness that
#      stubs hl.* and asserts every field round-trips with the
#      right type (numeric scale vs the "auto" string, transform
#      as a number)
#   3. environment.d — the REAL systemd user-environment generator
#      parses the serialized file; a Python decoder reverses the
#      generator's own escapes and asserts byte-exact values plus
#      the exact key set (a forged key would fail the comparison).
{
  pkgs,
  ...
}:
let
  lib = pkgs.lib;
  fmt = import ../../modules/lib/omarchy-formats.nix { inherit lib; };
  schema = (import ../../config.nix { inherit lib; }).omarchyOptions;

  # Evaluate just the omarchy option schema with the given
  # assignments; forcing .config.omarchy.<name> runs the module
  # system's type checks.
  omEval =
    assigns:
    (lib.evalModules {
      modules = [
        { options.omarchy = schema; }
        { omarchy = assigns; }
      ];
    }).config;

  # A negative case is a pair evaluated through the same accessor: the
  # rejected value must FAIL evaluation (option-type rejection or a fmt
  # throw; tryEval + deepSeq catches both) and a valid value — the
  # positive control — must succeed. tryEval cannot see the error text,
  # so without the control any failure would count as a rejection: a
  # renamed or misspelled option, a helper that throws on everything.
  assertNeg =
    name:
    { bad, good }:
    if !(builtins.tryEval (builtins.deepSeq good good)).success then
      throw "omarchy-option-validation: positive control does not evaluate: ${name}"
    else if (builtins.tryEval (builtins.deepSeq bad bad)).success then
      throw "omarchy-option-validation: negative case did NOT fail: ${name}"
    else
      true;
  # omarchy.<opt> = bad must be rejected, omarchy.<opt> = good accepted.
  optNeg =
    name: opt: bad: good:
    assertNeg name {
      bad = (omEval { ${opt} = bad; }).omarchy.${opt};
      good = (omEval { ${opt} = good; }).omarchy.${opt};
    };
  # A monitor entry the parser must reject, next to one it accepts.
  monNeg =
    name: bad: good:
    assertNeg name {
      bad = fmt.parseMonitor bad;
      good = fmt.parseMonitor good;
    };

  negativeCases = [
    (optNeg "scale-0" "scale" 0 1)
    (optNeg "scale-3" "scale" 3 2)
    (optNeg "theme-traversal" "theme" "../etc" "ethereal")
    (optNeg "theme-dot" "theme" "." "my.theme")
    (optNeg "theme-dotdot" "theme" ".." ".hidden")
    (optNeg "theme-slash" "theme" "a/b" "a-b")
    (optNeg "theme-newline" "theme" "a\nb" "a_b")
    (optNeg "terminal-newline" "terminal" "foot\nkitty" "kitty")
    (optNeg "full-name-lf" "full_name" "A\nB" "A B")
    (optNeg "full-name-cr" "full_name" "A\rB" "A B")
    (optNeg "email-lf" "email_address" "a@b\nc" "a@b.c")
    (optNeg "email-cr" "email_address" "a@b\rc" "a@b.c")
    (monNeg "monitor-empty-output" ", 1920x1080" "DP-1, 1920x1080")
    (monNeg "monitor-6-fields" "DP-1, preferred, auto, 1, 0, extra" "DP-1, preferred, auto, 1, 0")
    (monNeg "monitor-bad-scale" "DP-1, preferred, auto, abc" "DP-1, preferred, auto, 1.5")
    (monNeg "monitor-bad-transform" "DP-1, preferred, auto, 1, 8" "DP-1, preferred, auto, 1, 7")
    (monNeg "monitor-bad-auto-dir" "DP-1, preferred, auto-sideways, 1"
      "DP-1, preferred, auto-center-down, 1"
    )
    (monNeg "monitor-scale-below-quarter" "DP-1, preferred, auto, 0.2" "DP-1, preferred, auto, 0.25")
    (monNeg "monitor-scale-zero" "DP-1, preferred, auto, 0" "DP-1, preferred, auto, auto")
    (monNeg "monitor-bad-mode" "DP-1, 1920x" "DP-1, highrr")
    (monNeg "monitor-disable-extra-fields" "DP-1, disable, auto" "DP-1, disabled")
    (assertNeg "monitorsLuaText-scale-3" {
      bad = fmt.monitorsLuaText {
        scale = 3;
        monitors = [ ];
      };
      good = fmt.monitorsLuaText {
        scale = 2;
        monitors = [ ];
      };
    })
  ];

  monitorsLua = pkgs.writeText "monitors.lua" (
    fmt.monitorsLuaText {
      scale = 2;
      monitors = [
        "DP-1, 2560x1440@120, 0x0, 1.5, 2"
        ''HDMI-"quoted"\back\name, preferred, auto, auto''
        "tab\toutput"
        "DP-ąęść-🎮"
        "eDP-1"
        "DP-2, maxwidth, auto-center-right, 0.25"
        "HDMI-A-2, disable"
      ];
    }
  );

  envdConf = pkgs.writeText "50-omarchy.conf" (
    fmt.envdLines {
      OMARCHY_USER_NAME = ''John "JD" Doe \ $HOME'';
      OMARCHY_USER_EMAIL = "john+tag@example.com";
    }
    + "\n"
  );

  envdEmptyConf = pkgs.writeText "50-omarchy-empty.conf" (
    fmt.envdLines {
      OMARCHY_USER_NAME = "";
      OMARCHY_USER_EMAIL = "only-email@example.com";
    }
    + "\n"
  );

  luaHarness = pkgs.writeText "harness.lua" ''
    local captured = {}
    hl = {
      monitor = function(t) captured[#captured + 1] = t end,
      env = function() end,
    }
    dofile(os.getenv("MONITORS_LUA"))
    local function check(i, field, expected, want_type)
      local v = captured[i][field]
      assert(v ~= nil, string.format("entry %d field %s: missing", i, field))
      assert(type(v) == want_type,
        string.format("entry %d field %s: type %s, want %s", i, field, type(v), want_type))
      assert(tostring(v) == expected,
        string.format("entry %d field %s: got %q want %q", i, field, tostring(v), expected))
    end
    -- entry 1 is the catch-all; scale=2 -> omarchy_monitor_scale = "1.2"
    assert(captured[1].output == "", "catch-all output must be empty")
    assert(captured[1].scale == "1.2",
      "catch-all scale must be 1.2, got " .. tostring(captured[1].scale))
    check(2, "output", "DP-1", "string")
    check(2, "mode", "2560x1440@120", "string")
    check(2, "position", "0x0", "string")
    check(2, "scale", "1.5", "number")
    check(2, "transform", "2", "number")
    check(3, "output", os.getenv("EXP3_OUTPUT"), "string")
    check(3, "scale", "auto", "string") -- "auto" must stay a string
    check(4, "output", os.getenv("EXP4_OUTPUT"), "string")
    check(5, "output", os.getenv("EXP5_OUTPUT"), "string")
    check(6, "output", "eDP-1", "string")
    assert(captured[6].mode == nil, "eDP-1 must have no mode")
    check(7, "mode", "maxwidth", "string")
    check(7, "position", "auto-center-right", "string")
    check(7, "scale", "0.25", "number")
    check(8, "output", "HDMI-A-2", "string")
    check(8, "disabled", "true", "boolean")
    assert(captured[8].mode == nil, "a disabled output must carry no mode")
    assert(captured[2].disabled == nil, "an enabled output must not carry disabled")
    assert(#captured == 8, "expected 8 hl.monitor calls, got " .. #captured)
    print("lua harness OK")
  '';

  # Reverse the generator's own output escapes and compare
  # byte-exact; the whole-dict comparison also proves no key was
  # injected beyond PATH (which the generator always prints).
  envdDecode = pkgs.writeText "envd-decode.py" ''
    import os, sys

    def decode(val):
        # Generator serializer escapes (inside quotes):
        # \\ -> \, \$ -> $, \" -> ", \n -> NL, \t -> TAB
        mapping = {'\\': '\\', '$': '$', '"': '"', 'n': '\n', 't': '\t'}
        out = []
        i = 0
        while i < len(val):
            if val[i] == '\\' and i + 1 < len(val) and val[i + 1] in mapping:
                out.append(mapping[val[i + 1]])
                i += 2
            else:
                out.append(val[i])
                i += 1
        return '''.join(out)

    expected = {
        'OMARCHY_USER_NAME': os.environ['EXP_NAME'],
        'OMARCHY_USER_EMAIL': 'john+tag@example.com',
    }
    seen = {}
    with open('gen.out') as fh:
        for line in fh:
            line = line.rstrip('\n')
            if '=' not in line:
                continue
            k, v = line.split('=', 1)
            if k == 'PATH':
                continue
            if len(v) >= 2 and v.startswith('"') and v.endswith('"'):
                v = decode(v[1:-1])
            seen[k] = v

    if seen != expected:
        sys.stderr.write(f"envd mismatch:\nseen     = {seen!r}\nexpected = {expected!r}\n")
        sys.exit(1)
    print("envd round-trip OK")
  '';
in
pkgs.runCommand "omarchy-option-validation-check"
  {
    nativeBuildInputs = [
      pkgs.lua5_4
      pkgs.python3
    ];
    # Forcing this env var at instantiation time evaluates every
    # negative case: a regression throws during EVAL, before the
    # builder even runs.
    negativeCases = lib.concatStringsSep "," (map toString negativeCases);
  }
  ''
    set -euo pipefail
    fail() { echo "FAIL: $*" >&2; exit 1; }

    # --- monitors.lua: syntax + semantics -----------------------
    luac -p ${monitorsLua} || fail "luac -p rejected monitors.lua"
    export MONITORS_LUA=${monitorsLua}
    export EXP3_OUTPUT='HDMI-"quoted"\back\name'
    export EXP4_OUTPUT=$'tab\toutput'
    export EXP5_OUTPUT='DP-ąęść-🎮'
    lua ${luaHarness} || fail "lua harness"

    # --- environment.d: real systemd generator round-trip -------
    GENERATOR="${pkgs.systemd}/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
    export HOME=$TMPDIR/home
    mkdir -p "$HOME/.config/environment.d"
    # cp -f: store sources are read-only, so a plain second cp
    # cannot overwrite the first copy.
    cp -f ${envdConf} "$HOME/.config/environment.d/50-omarchy.conf"
    "$GENERATOR" > gen.out 2> gen.err
    ! grep -q "invalid syntax" gen.err || { cat gen.err; fail "generator rejected 50-omarchy.conf"; }
    EXP_NAME='John "JD" Doe \ $HOME' python3 ${envdDecode} || fail "envd round-trip"

    # --- empty values are omitted, file still parses clean ------
    cp -f ${envdEmptyConf} "$HOME/.config/environment.d/50-omarchy.conf"
    "$GENERATOR" > gen2.out 2> gen2.err
    ! grep -q "invalid syntax" gen2.err || { cat gen2.err; fail "generator rejected empty-name conf"; }
    grep -q '^OMARCHY_USER_EMAIL=only-email@example.com$' gen2.out ||
      fail "email missing from empty-name run: $(cat gen2.out)"
    ! grep -q 'OMARCHY_USER_NAME' gen2.out ||
      fail "empty OMARCHY_USER_NAME must be omitted"

    touch $out
  ''
