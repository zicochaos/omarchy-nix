echo "Let Neovim's current line and status line show the terminal background"

# NixOS adapter of 1791723398: same layout as 1781587663 — omarchy-nvim is not
# under /usr/share. Use the system or per-user profile when it links
# share/omarchy-nvim, else the package behind the omarchy-nvim-setup command.
config="$HOME/.config/nvim"
files=(plugin/after/transparency.lua lua/plugins/lualine-transparent.lua)

package=""
nvim_setup=$(command -v omarchy-nvim-setup 2>/dev/null) && nvim_setup=$(readlink -f -- "$nvim_setup") || nvim_setup=""
for cand in \
  /run/current-system/sw/share/omarchy-nvim/config \
  "/etc/profiles/per-user/${USER:-}/share/omarchy-nvim/config" \
  ${nvim_setup:+"${nvim_setup%/bin/omarchy-nvim-setup}/share/omarchy-nvim/config"}; do
  if [[ -f $cand/${files[1]} ]]; then
    package=$cand
    break
  fi
done

[[ -d $config ]] || exit 0

# Dotfile managers may own a file or a parent directory through a symlink.
# Preserve that layout rather than detaching or editing its target.
for file in "${files[@]}"; do
  path="$config/$file"
  while [[ $path != "$HOME" && $path != / ]]; do
    if [[ -L $path ]]; then
      echo "Preserving symlink-managed Neovim config: $path"
      exit 0
    fi
    path=$(dirname "$path")
  done
done

# Nothing to copy until an omarchy-nvim carrying the files is on the profile.
[[ -n $package ]] || {
  echo "NixOS: omarchy-nvim transparency sources not found; skipping." >&2
  exit 0
}

# A copy staged beside its target and moved into place whole, so a failed
# write leaves the original for a retry.
staged=""
trap 'rm -f -- ${staged:+"$staged"}' EXIT
install_from_package() {
  staged=$(mktemp "$config/$1.new.XXXXXX")
  install -m 0644 "$package/$1" "$staged"
  mv -fT -- "$staged" "$config/$1"
}

# Only a transparency file still as Omarchy shipped it is replaced, so one the
# user changed is kept.
if [[ -f $config/${files[0]} ]]; then
  case $(sha256sum <"$config/${files[0]}") in
    bd833dc094e3546b5fad512e61cfb09f3032c2a4461c23be7bd90851de80688e* | \
      6e31b917f13e16514ac94ff9270d47f24e76509a3e559ca85116a5aa2d61306a* | \
      33d29360df84ed48c70606580749536520384ec64afe650151d4e26e7922b410*)
      install_from_package "${files[0]}"
      ;;
  esac
fi

if [[ -d $config/lua/plugins && ! -e $config/${files[1]} ]]; then
  install_from_package "${files[1]}"
fi
