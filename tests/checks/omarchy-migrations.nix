# Migration manifest consistency: every vendored
# migration must be classified in pkgs/omarchy-migrations.nix
# (unclassified = fail), every manifest key must exist in the
# vendored set (stale = fail), and every "adapter" class must have
# its replacement script in pkgs/migrations-nix/.
{
  self,
  pkgs,
  system,
  ...
}:
let
  manifestJson = pkgs.writeText "migrations-nix.json" (
    builtins.toJSON (import ../../pkgs/omarchy-migrations.nix)
  );
  vendored = "${self.packages.${system}.omarchy}/share/omarchy/migrations";
  adapters = ../../pkgs/migrations-nix;
in
pkgs.runCommand "omarchy-migrations-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  ls ${vendored}/*.sh | xargs -n1 basename | sort > vendored.txt
  jq -r 'keys[]' ${manifestJson} | sort > manifest.txt

  unclassified=$(comm -23 vendored.txt manifest.txt)
  if [[ -n $unclassified ]]; then
    echo "vendored migrations missing from pkgs/omarchy-migrations.nix:"
    echo "$unclassified"
    exit 1
  fi

  stale=$(comm -13 vendored.txt manifest.txt)
  if [[ -n $stale ]]; then
    echo "stale keys in pkgs/omarchy-migrations.nix (not vendored anymore):"
    echo "$stale"
    exit 1
  fi

  # Captured first: a failing jq inside `for … in $(…)` would not trip
  # set -e and the loop would just run zero times.
  adapter_list=$(jq -r 'to_entries[] | select(.value == "adapter") | .key' ${manifestJson})
  [[ -n $adapter_list ]] || { echo "no adapter-class migrations in the manifest (expected the pkgs/migrations-nix set)"; exit 1; }
  for f in $adapter_list; do
    [[ -f ${adapters}/$f ]] || { echo "adapter classified but missing: pkgs/migrations-nix/$f"; exit 1; }
  done

  bad=$(jq -r 'to_entries[] | select(.value != "skip" and .value != "user-safe" and .value != "adapter") | .key' ${manifestJson})
  if [[ -n $bad ]]; then
    echo "unknown migration class (want skip|user-safe|adapter):"
    echo "$bad"
    exit 1
  fi

  # The new notification engine retires old message content while carrying
  # DND forward. A shell that has already written quiet state wins over the
  # legacy flag; retrying the migration must preserve that state too.
  notificationHome=$TMPDIR/notification-home
  notificationState=$notificationHome/.local/state/omarchy
  mkdir -p "$notificationState/notifications/history" "$notificationState/notifications/images"
  printf '{"dnd":true}\n' >"$notificationState/notifications.json"
  printf '{}\n' >"$notificationState/notifications/123-message.json"
  HOME="$notificationHome" ${pkgs.bash}/bin/bash ${vendored}/1792648436.sh
  jq -e '.dnd == true and .snoozes == {} and .codesBypassQuiet == true' \
    "$notificationState/notifications/quiet.json"
  test "$(stat -c %a "$notificationState/notifications/quiet.json")" = 600
  test ! -e "$notificationState/notifications.json"
  test ! -e "$notificationState/notifications/history"
  test ! -e "$notificationState/notifications/images"
  test ! -e "$notificationState/notifications/123-message.json"
  printf '{"dnd":false,"snoozes":{"chat":123}}\n' >"$notificationState/notifications/quiet.json"
  cp "$notificationState/notifications/quiet.json" expected-quiet.json
  printf '{"dnd":true}\n' >"$notificationState/notifications.json"
  HOME="$notificationHome" ${pkgs.bash}/bin/bash ${vendored}/1792648436.sh
  cmp expected-quiet.json "$notificationState/notifications/quiet.json"
  HOME="$notificationHome" ${pkgs.bash}/bin/bash ${vendored}/1792648436.sh
  cmp expected-quiet.json "$notificationState/notifications/quiet.json"

  # Runner stdin: the packaged omarchy-migrate against a temp root. A
  # migration that reads stdin (gum confirm, read) must get the
  # caller's stdin, never the pending list (it used to swallow the
  # rest of the queue: later migrations were silently skipped and the
  # run still exited 0). fd 3 (where the list now travels) must be
  # closed for the migration.
  R=$TMPDIR/mig
  mkdir -p "$R/root/migrations" "$R/state"
  printf '%s\n' "cat >$R/a-stdin" \
    "if { true <&3; } 2>/dev/null; then touch $R/a-fd3-open; fi" \
    >"$R/root/migrations/1000000001.sh"
  printf '%s\n' "touch $R/b-ran" >"$R/root/migrations/1000000002.sh"
  printf '%s\n' "touch $R/c-ran" >"$R/root/migrations/1000000003.sh"
  echo '{"1000000001.sh":"user-safe","1000000002.sh":"user-safe","1000000003.sh":"user-safe"}' \
    >"$R/root/migrations-nix.json"
  printf 'user-input\n' |
    OMARCHY_PATH=$R/root OMARCHY_MIGRATION_STATE=$R/state \
      ${self.packages.${system}.omarchy}/share/omarchy/bin/omarchy-migrate >"$R/log" 2>&1 ||
    { cat "$R/log"; echo "omarchy-migrate failed"; exit 1; }
  for m in b c; do
    [[ -e $R/$m-ran ]] || { cat "$R/log"; echo "migration $m was skipped: an earlier migration swallowed the pending list"; exit 1; }
  done
  for n in 1 2 3; do
    [[ -f $R/state/100000000$n.sh ]] || { echo "migration 100000000$n.sh not marked as applied"; exit 1; }
  done
  [[ $(cat "$R/a-stdin") == user-input ]] ||
    { echo "migration did not receive the caller's stdin: $(cat "$R/a-stdin")"; exit 1; }
  [[ ! -e $R/a-fd3-open ]] || { echo "the pending-list fd 3 leaked into the migration"; exit 1; }

  touch $out
''
