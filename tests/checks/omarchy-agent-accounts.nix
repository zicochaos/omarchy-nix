# Account dispatch contract: exercise the packaged wrappers and registry with
# fixture identities and CLI probes, never a real provider or login service.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  providerProbe = pkgs.writeScript "omarchy-account-provider-probe" ''
    #!${pkgs.python3}/bin/python3
    import json
    import os
    import subprocess
    import sys
    from pathlib import Path

    provider = Path(sys.argv[0]).name
    home_env = {"claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME", "grok": "GROK_HOME"}[provider]
    data = {
        "provider": provider,
        "args": sys.argv[1:],
        "home": os.environ.get(home_env),
        "effectiveHome": os.environ.get(home_env) or str(Path.home() / ("." + provider)),
        "pin": os.environ.get("OMARCHY_AGENT_" + provider.upper() + "_HOME"),
    }
    if sys.argv[1:2] == ["--switch-and-spawn"]:
        subprocess.run(
            ["omarchy-agent-account-state", "use", provider, sys.argv[2]],
            check=True, capture_output=True, text=True,
        )
        child = subprocess.run([provider, "child", "two words"], check=True, capture_output=True, text=True)
        data["child"] = json.loads(child.stdout)
    elif sys.argv[1:2] == ["--spawn-provider"]:
        child = subprocess.run([sys.argv[2], *sys.argv[3:]], check=True, capture_output=True, text=True)
        data["child"] = json.loads(child.stdout)
    print(json.dumps(data))
  '';
  supportPath = pkgs.lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.jq
    pkgs.util-linux
  ];
in
pkgs.runCommand "omarchy-agent-accounts-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  set -euo pipefail
  export HOME=$TMPDIR/home
  export XDG_CONFIG_HOME=$HOME/.config
  export XDG_STATE_HOME=$TMPDIR/state
  export XDG_CACHE_HOME=$TMPDIR/cache
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

  python3 <<'PY'
  import json
  import os
  import subprocess
  from pathlib import Path

  root = Path(os.environ["TMPDIR"])
  home = Path(os.environ["HOME"])
  package = Path("${omarchyPkg}/share/omarchy")
  omarchy = root / "omarchy-profile"
  omarchy.symlink_to(package, target_is_directory=True)
  wrapper_alias = root / "wrapper-alias"
  wrapper_alias.symlink_to(package / "agent-wrappers", target_is_directory=True)
  provider_bin = root / "providers"
  provider_bin.mkdir()
  env_names = {"claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME", "grok": "GROK_HOME"}
  arch_names = {"claude": "claude-code", "codex": "codex-cli", "grok": "grok-cli"}
  for provider in env_names:
      (provider_bin / provider).symlink_to("${providerProbe}")

  # Explicit empty consumer state keeps package presence checks independent
  # of any host flake and makes them exercise the underlying CLI fallback.
  consumer = root / "consumer"
  consumer.mkdir()
  (consumer / "flake.nix").write_text("# account dispatch fixture\n")
  (consumer / "omarchy-packages.json").write_text('{"packages": [], "features": []}\n')
  base = dict(os.environ, OMARCHY_PATH=str(omarchy), OMARCHY_NIX_FLAKE=str(consumer))
  for key in [*env_names.values(), *("OMARCHY_AGENT_" + p.upper() + "_HOME" for p in env_names)]:
      base.pop(key, None)
  wrappers = [str(wrapper_alias), str(omarchy / "agent-wrappers") + "/../agent-wrappers", str(package / "agent-wrappers")]
  installed_path = ":".join([*wrappers, str(provider_bin), str(omarchy / "bin"), "${supportPath}"])
  absent_path = ":".join([*wrappers, str(omarchy / "bin"), "${supportPath}"])
  base["PATH"] = installed_path

  def run(args, expected=0, env=None, cwd=None):
      result = subprocess.run(args, env=env or base, cwd=cwd, text=True, capture_output=True, timeout=10)
      assert result.returncode == expected, (args, result.returncode, expected, result.stdout, result.stderr)
      return result

  def probe(provider, *args, env=None):
      return json.loads(run([provider, *args], env=env).stdout)

  def state(*args):
      return run(["omarchy-agent-account-state", *args]).stdout.strip()

  # The default Main account remains implicit, including an empty pin, so
  # Claude retains its ordinary ~/.claude.json behavior. Wrappers preserve
  # spaces, empty arguments and literal shell syntax without re-parsing them.
  arguments = ["two words", "", "--option=a b", "$(literal); *"]
  for provider in env_names:
      result = probe(provider, *arguments)
      assert result["provider"] == provider and result["args"] == arguments, result
      assert result["home"] is None and result["pin"] == "", result
      assert result["effectiveHome"] == str(home / ("." + provider)), result
      assert run(["omarchy-agent-account-home", provider]).stdout == ""
      run(["omarchy-cmd-present", provider])
      run(["omarchy-cmd-missing", provider], expected=1)
      run(["omarchy-pkg-present", provider])
      run(["omarchy-pkg-present", arch_names[provider]])

  # Register fixture sign-ins through upstream's actual pending-home and
  # registry operations. No authentication command or network request runs.
  accounts = {}
  for provider in env_names:
      pending = Path(state("begin", provider))
      if provider == "claude":
          (pending / ".claude.json").write_text(json.dumps({"oauthAccount": {"accountUuid": "fixture-claude", "emailAddress": "claude@example.invalid"}}))
          # 33783b1: register also requires a completed OAuth login in
          # .credentials.json (claudeAiOauth), not just the account file.
          (pending / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {"subscriptionType": "pro"}}))
      elif provider == "codex":
          (pending / "auth.json").write_text(json.dumps({"tokens": {"account_id": "fixture-codex"}}))
      else:
          (pending / "auth.json").write_text(json.dumps({"fixture": {"user_id": "fixture-grok", "email": "grok@example.invalid"}}))
      accounts[provider] = json.loads(state("register", provider, "Work", str(pending)))

      # Switching the registry inside a running Main session must not switch
      # its child. A fresh invocation must pick up the newly selected Work.
      main = probe(provider, "--switch-and-spawn", accounts[provider]["id"])
      assert main["child"]["home"] is None and main["child"]["pin"] == "", main
      selected = probe(provider)
      assert selected["home"] == accounts[provider]["home"] and selected["pin"] == selected["home"], selected
      assert run(["omarchy-agent-account-home", provider]).stdout.strip() == selected["home"]

      # A running selected account also stays pinned when new sessions switch
      # back to Main. Explicit provider homes always override the registry.
      pinned = probe(provider, "--switch-and-spawn", "main")
      assert pinned["child"]["home"] == accounts[provider]["home"], pinned
      assert pinned["child"]["pin"] == accounts[provider]["home"], pinned
      fresh_main = probe(provider)
      assert fresh_main["home"] is None and fresh_main["pin"] == "", fresh_main
      state("use", provider, accounts[provider]["id"])
      explicit = str(root / ("explicit " + provider))
      pin_env = "OMARCHY_AGENT_" + provider.upper() + "_HOME"
      result = probe(provider, env=dict(base, **{env_names[provider]: explicit, pin_env: accounts[provider]["home"]}))
      assert result["home"] == explicit and result["effectiveHome"] == explicit, result

  # A provider launched by another provider must pass through account
  # dispatch again; calling its raw CLI would leave its home implicit.
  nested = probe("claude", "--spawn-provider", "codex", "nested argument", "")
  assert nested["child"]["provider"] == "codex", nested
  assert nested["child"]["args"] == ["nested argument", ""], nested
  assert nested["child"]["home"] == accounts["codex"]["home"], nested

  # Empty PATH fields mean the current directory. Preserve that lookup when
  # it contains a real CLI, while filtering it when it contains dispatchers.
  working_path = ":".join([*wrappers, "${supportPath}"])
  for path in (working_path + ":", ":" + working_path):
      for provider in env_names:
          current = dict(base, PATH=path, **{env_names[provider]: accounts[provider]["home"]})
          result = json.loads(run([str(package / "agent-wrappers" / provider), "current directory"], env=current, cwd=provider_bin).stdout)
          assert result["provider"] == provider and result["args"] == ["current directory"], result
          assert result["home"] == accounts[provider]["home"], result
          run([str(package / "bin/omarchy-cmd-present"), provider], env=current, cwd=provider_bin)
          run([str(package / "bin/omarchy-cmd-missing"), provider], expected=1, env=current, cwd=provider_bin)
          run([str(package / "bin/omarchy-pkg-present"), arch_names[provider]], env=current, cwd=provider_bin)
  for path in ("${supportPath}:", ":${supportPath}"):
      for provider in env_names:
          current = dict(base, PATH=path, **{env_names[provider]: accounts[provider]["home"]})
          result = run([str(package / "agent-wrappers" / provider)], expected=127, env=current, cwd=package / "agent-wrappers")
          assert "omarchy-nix-add install.ai." + provider in result.stderr, result.stderr
          run([str(package / "bin/omarchy-cmd-present"), provider], expected=1, env=current, cwd=package / "agent-wrappers")
          run([str(package / "bin/omarchy-cmd-missing"), provider], env=current, cwd=package / "agent-wrappers")
          run([str(package / "bin/omarchy-pkg-present"), arch_names[provider]], expected=1, env=current, cwd=package / "agent-wrappers")

  # Dispatchers alone are not installed CLIs. Canonical aliases and a
  # relative '.' entry must be filtered for both dispatch and presence probes.
  for path, cwd in [(absent_path, None), (".:" + absent_path, package / "agent-wrappers")]:
      absent = dict(base, PATH=path)
      for provider in env_names:
          result = run([provider], expected=127, env=absent, cwd=cwd)
          assert "omarchy-nix-add install.ai." + provider in result.stderr, result.stderr
          run(["omarchy-cmd-present", provider], expected=1, env=absent, cwd=cwd)
          run(["omarchy-cmd-missing", provider], env=absent, cwd=cwd)
          run(["omarchy-pkg-present", provider], expected=1, env=absent, cwd=cwd)
          run(["omarchy-pkg-present", arch_names[provider]], expected=1, env=absent, cwd=cwd)

  print("Agent account dispatch passed: Main/selected/explicit homes, session pins, argv, nested dispatch, absent CLI guards, PATH aliases and empty fields.")
  PY
  touch $out
''
