# Runtime mutator quarantine: scan the packaged tree for forbidden Arch
# mutation patterns — every regular file in bin/ (whatever its mode),
# install/user/** (run by first-run/finalize-user), default/bash/fns/*
# (sourced by interactive bash), the user-safe vendored migrations and
# the NixOS migration adapters. Any sudo/pkexec invocation is a pattern
# group of its own (the catch-all for privileged mutations no specific
# pattern names). A hit must be classified in
# pkgs/omarchy-runtime-manifest.nix (bin scripts under `scripts`, other
# files by path under `files`); user-safe, nixos-adapted and port-owned
# entries may only keep their declared `allow` groups, and every declared
# group must still hit. A NEW upstream mutator is unclassified and FAILS
# the build — classification is forced at bump time. Declarative-note
# stubs are verified by output instead (exactly their manifest note).
# Manifest keys are checked against the UPSTREAM tree (the packaged one
# always has the generated stubs), and the hidden menu ids must be gone
# with no menu entry referencing a stubbed mutator.
{
  self,
  pkgs,
  system,
  ...
}:
let
  omarchyPkg = self.packages.${system}.omarchy;
  manifestJson = pkgs.writeText "omarchy-runtime-manifest.json" (
    builtins.toJSON (import ../../pkgs/omarchy-runtime-manifest.nix)
  );
  migrationsJson = pkgs.writeText "migrations-nix.json" (
    builtins.toJSON (import ../../pkgs/omarchy-migrations.nix)
  );
in
pkgs.runCommand "omarchy-runtime-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
  root=${omarchyPkg}/share/omarchy
  upstream=${omarchyPkg.src}
  bin=$root/bin
  migrations=$root/migrations
  menu=$root/default/omarchy/omarchy-menu.jsonc
  manifest=${manifestJson}
  migManifest=${migrationsJson}
  # The loops below read these through `< <(jq …)`, whose exit status
  # nothing checks; validating the documents once up front means a jq
  # failure there can only come from a filter bug, not from bad input.
  jq -e '.scripts | type == "object"' "$manifest" >/dev/null
  jq -e 'type == "object" and length > 0' "$migManifest" >/dev/null
  bad=0

  # Pattern groups (ERE, matched per line after stripping full-line
  # comments). excl[g] drops matching lines that also match it (systemctl
  # with --user is the user group, not the system ones).
  declare -A pat excl
  # pacman with flags or expanded arguments, and a bare `pacman` word
  # ending a token (PM=pacman; $PM -S …, cmd=(sudo pacman)) — not the
  # tail of a hyphenated command name (omarchy-update-pacman)
  pat[pacman]='(^|[^[:alnum:]_-])pacman([[:space:]]+(-|"|'"'"'|\$)|["'"'"']?[[:space:]]*($|[;&|)]))'
  pat[pkg-helpers]='\b(yay|paru|makepkg)\b'
  pat[ufw]='\bufw[[:space:]]'
  ctl_opts='([[:space:]]+-[^[:space:]]+)*'
  pat[systemctl-system]="\\bsystemctl''${ctl_opts}[[:space:]]+(enable|disable|mask|unmask)([[:space:]]|\$)"
  excl[systemctl-system]='--user'
  # transient system-service control (no persistent config)
  pat[systemctl-restart]="\\bsystemctl''${ctl_opts}[[:space:]]+(start|stop|restart|reload|try-restart|reload-or-restart)([[:space:]]|\$)"
  excl[systemctl-restart]='--user'
  pat[systemctl-user]="\\bsystemctl''${ctl_opts}[[:space:]]+--user''${ctl_opts}[[:space:]]+(enable|disable|mask|unmask|start|stop|restart)"
  pat[etc-sysconf]='/etc/(pam\.d|sudoers|fstab|systemd/system|systemd/resolved|systemd/network|NetworkManager|mkinitcpio|modprobe\.d|modules-load\.d|omarchy\.conf|limine|opt/chrome|opt/edge|brave|chromium|php)'
  # write verbs targeting /etc, /boot, /var or /usr/share (over-match
  # reads like cp /etc/skel on purpose — classification then audits them)
  pat[etc-write]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/etc/|/etc$)|(>>?)[[:space:]]*/etc/'
  pat[boot-write]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/boot/|/boot$)|(>>?)[[:space:]]*/boot/'
  pat[var-write]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/var/|/var$)|(>>?)[[:space:]]*/var/'
  pat[usr-share]='(sudo[[:space:]]+)?(tee|install|cp|mv|rm|mkdir|chmod|chown|ln|sed)[[:space:]][^;&|]*(/usr/share/|/usr/share$)|(>>?)[[:space:]]*/usr/share/'
  pat[usr-lib]='/usr/lib/(systemd|modules)'
  pat[initrd-boot]='\b(mkinitcpio|limine-mkinitcpio|limine-update|limine-snapper-sync|plymouth-set-default-theme|grub-mkconfig|update-grub|efibootmgr|bootctl)\b'
  pat[snapper]='\bsnapper\b'
  pat[modprobe]='\b(modprobe|insmod|rmmod)\b'
  # transient rfkill device state (soft block/unblock)
  pat[rfkill]='\brfkill[[:space:]]+(block|unblock)\b'
  # NetworkManager runtime radio/network state (no profile writes)
  pat[nmcli-radio]='\bnmcli[[:space:]]+(radio|networking|device[[:space:]]+wifi[[:space:]]+rescan)\b'
  pat[kernel-ctl]='\bsysctl[[:space:]]+(-w|--write|-p[[:space:]])'
  pat[account-tools]='\b(usermod|useradd|userdel|groupadd|groupdel|gpasswd|chsh|visudo|chpasswd)\b'
  pat[ctl-set]='\b(timedatectl|hostnamectl|localectl)[[:space:]]+set-'
  # catch-all: any privileged invocation, however it is spelled
  pat[sudo]='(^|[^[:alnum:]_./-])(sudo|pkexec)([[:space:]]|$)|/(run/wrappers|usr)/bin/(sudo|pkexec)\b'

  # scan <file> — sets $hits to the matching groups (space-separated)
  scan() {
    local g
    hits=""
    grep -v '^[[:space:]]*#' "$1" >scan.txt || true
    for g in $(printf '%s\n' "''${!pat[@]}" | sort); do
      if [[ -n ''${excl[$g]:-} ]]; then
        grep -E -- "''${pat[$g]}" scan.txt | grep -vqE -- "''${excl[$g]}" && hits="$hits $g"
      else
        grep -Eq -- "''${pat[$g]}" scan.txt && hits="$hits $g"
      fi
    done
    hits=''${hits# }
  }

  # judge <label> <class> <allow...> — the classified-entry rules
  judge() {
    local label=$1 class=$2 g
    shift 2
    case "$class" in
      user-safe | nixos-adapted | port-owned)
        for g in $hits; do
          if [[ " $* " != *" $g "* ]]; then
            echo "$class $label keeps undeclared pattern group: $g"
            bad=1
          fi
        done
        for g in "$@"; do
          if [[ " $hits " != *" $g "* ]]; then
            echo "$class $label declares allow group $g, which no longer matches (drop it)"
            bad=1
          fi
        done
        ;;
      *)
        echo "$label: unknown class '$class' (want user-safe|nixos-adapted|port-owned|declarative-note)"
        bad=1
        ;;
    esac
  }

  # Scanner self-test: every invocation form below must hit its group
  # (expect "<group> <line>"), and the "!" lines must NOT hit it.
  while IFS= read -r t; do
    neg=0
    [[ $t == '!'* ]] && { neg=1; t=''${t#!}; }
    g=''${t%% *}
    printf '%s\n' "''${t#* }" >selftest.sh
    scan selftest.sh
    if ((neg == 0)) && [[ " $hits " != *" $g "* ]]; then
      echo "scanner self-test: '$(cat selftest.sh)' does not hit $g (hits: $hits)"
      bad=1
    elif ((neg == 1)) && [[ " $hits " == *" $g "* ]]; then
      echo "scanner self-test: '$(cat selftest.sh)' must not hit $g"
      bad=1
    fi
  done <<'SELFTEST'
  pacman sudo pacman -Syu --noconfirm
  pacman exec sudo env "''${env_args[@]}" pacman "$@"
  pacman sudo pacman $flags
  pacman PM=pacman
  pkg-helpers yay
  pkg-helpers AUR_HELPER=paru
  systemctl-system sudo systemctl --now enable sshd
  systemctl-system sudo systemctl -q enable ufw.service
  !systemctl-system systemctl --user --now enable owed.service
  systemctl-user systemctl --user --now enable owed.service
  systemctl-restart sudo systemctl restart systemd-timesyncd
  snapper sudo snapper -c root create -d pre-update
  var-write echo state | sudo tee /var/lib/sddm/state.conf
  etc-write echo x | sudo tee -a /etc/hosts
  sudo pkexec usermod -aG input "$USER"
  sudo exec pkexec "$PACKAGED_PATH" "$@"
  sudo /run/wrappers/bin/sudo -n true
  sudo /usr/bin/sudo rm -f /usr/local/bin/opam
  sudo printf %s "$pw" | sudo bash -c 'cryptsetup luksChangeKey "$1"' bash "$d"
  !pacman echo "NixOS: handled declaratively (via omarchy-update-pacman)"
  !sudo omarchy-sudo-passwordless
  !sudo cat /etc/sudoers.d/omarchy
  SELFTEST

  # manifest allow-groups must be known pattern groups
  while read -r n g; do
    [[ -n ''${pat[$g]+x} ]] || { echo "manifest: $n allows unknown pattern group: $g"; bad=1; }
  done < <(jq -r '(.scripts, .files) | to_entries[] | .key as $k | (.value.allow // [])[] | "\($k) \(.)"' "$manifest")

  # --- bin/: every regular file, whatever its mode ------------------
  # (upstream ships some scripts non-executable, and the library
  # omarchy-nix-pkglib is 0644 by design)
  for f in "$bin"/*; do
    [[ -f $f ]] || continue
    name=$(basename "$f")
    class=$(jq -r --arg n "$name" '.scripts[$n].class // ""' "$manifest")
    # verified by output below
    [[ $class == declarative-note ]] && continue
    scan "$f"
    if [[ -z $class ]]; then
      if [[ -n $hits ]]; then
        echo "UNCLASSIFIED mutator: bin/$name -> $hits"
        bad=1
      fi
      continue
    fi
    mapfile -t allow < <(jq -r --arg n "$name" '.scripts[$n].allow // [] | .[]' "$manifest")
    judge "bin/$name" "$class" "''${allow[@]}"
  done

  # --- install/user/** and default/bash/fns/*: classified by path ----
  while IFS= read -r f; do
    rel=''${f#"$root"/}
    class=$(jq -r --arg n "$rel" '.files[$n].class // ""' "$manifest")
    scan "$f"
    if [[ -z $class ]]; then
      if [[ -n $hits ]]; then
        echo "UNCLASSIFIED mutator: $rel -> $hits"
        bad=1
      fi
      continue
    fi
    mapfile -t allow < <(jq -r --arg n "$rel" '.files[$n].allow // [] | .[]' "$manifest")
    judge "$rel" "$class" "''${allow[@]}"
  done < <(find "$root/install/user" "$root/default/bash/fns" -type f | sort)

  # --- migrations: user-safe vendored ones and the NixOS adapters run
  # at login as-is. systemctl --user is part of the user-safe class
  # definition (see pkgs/omarchy-migrations.nix) and is allowed; any
  # other hit means a misclassification (e.g. sudo /etc write).
  for f in "$migrations"/*.sh "$root"/migrations-nix/*.sh; do
    [[ -f $f ]] || continue
    name=$(basename "$f")
    if [[ $f == "$migrations"/* ]]; then
      class=$(jq -r --arg n "$name" '.[$n] // ""' "$migManifest")
      [[ $class == user-safe ]] || continue
    fi
    scan "$f"
    for g in $hits; do
      if [[ $g != systemctl-user ]]; then
        echo "migration ''${f#"$root"/} keeps forbidden pattern group: $g"
        bad=1
      fi
    done
  done

  # --- stale manifest keys, against the UPSTREAM tree ---------------
  # (generated stubs make every key exist in the packaged bin/)
  while IFS=$'\t' read -r n class; do
    if [[ $class == port-owned ]]; then
      [[ -f $bin/$n ]] || { echo "stale port-owned key (not in packaged bin): $n"; bad=1; }
      [[ ! -e $upstream/bin/$n ]] || { echo "port-owned $n now exists upstream: reclassify it"; bad=1; }
    else
      [[ -f $upstream/bin/$n ]] || { echo "stale manifest key (not in upstream bin): $n"; bad=1; }
    fi
  done < <(jq -r '.scripts | to_entries[] | [.key, .value.class] | @tsv' "$manifest")
  while read -r n; do
    [[ -f $upstream/$n ]] || { echo "stale manifest file key (not upstream): $n"; bad=1; }
  done < <(jq -r '.files | keys[]' "$manifest")

  # hidden menu ids must be gone
  while read -r id; do
    if grep -qF "\"$id\":" "$menu"; then echo "menu entry not hidden: $id"; bad=1; fi
  done < <(jq -r '.hiddenMenuIds[]' "$manifest")

  # menu must not reference any stubbed (declarative-note) mutator
  while read -r n; do
    if grep -qF "$n" "$menu"; then echo "menu still references stubbed mutator: $n"; bad=1; fi
  done < <(jq -r '.scripts | to_entries[] | select(.value.class == "declarative-note") | .key' "$manifest")

  # declarative-note stubs are the generated ones (not upstream's
  # script) and print their manifest note verbatim — quotes included,
  # nothing expanded — then exit 0
  while read -r n; do
    note=$(jq -r --arg n "$n" '.scripts[$n].note' "$manifest")
    expected=$(printf 'NixOS: %s\n(via %s — neutralized; nothing was changed)' "$note" "$n")
    if ! got=$("$bin/$n" 2>&1); then
      echo "declarative-note stub exited non-zero: $n"
      bad=1
    elif [[ $got != "$expected" ]]; then
      printf 'declarative-note stub %s prints:\n%s\nexpected:\n%s\n' "$n" "$got" "$expected"
      bad=1
    fi
  done < <(jq -r '.scripts | to_entries[] | select(.value.class == "declarative-note") | .key' "$manifest")

  [[ $bad == 0 ]] || exit 1
  touch $out
''
