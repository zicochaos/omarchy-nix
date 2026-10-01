echo "Enable secure remote Neovim clipboard support"

nvim_config_dir="$HOME/.config/nvim"
nvim_options="$nvim_config_dir/lua/config/options.lua"
nvim_provider="$nvim_config_dir/lua/config/remote_clipboard.lua"

# NixOS: omarchy-nvim is not under /usr/share. Use the system or per-user
# profile when it links share/omarchy-nvim, else the package behind the
# omarchy-nvim-setup command (by default the profile links only that).
provider_source=""
nvim_setup=$(command -v omarchy-nvim-setup 2>/dev/null) && nvim_setup=$(readlink -f -- "$nvim_setup") || nvim_setup=""
for cand in \
  /run/current-system/sw/share/omarchy-nvim/config/lua/config/remote_clipboard.lua \
  "/etc/profiles/per-user/${USER:-}/share/omarchy-nvim/config/lua/config/remote_clipboard.lua" \
  ${nvim_setup:+"${nvim_setup%/bin/omarchy-nvim-setup}/share/omarchy-nvim/config/lua/config/remote_clipboard.lua"}; do
  if [[ -f $cand ]]; then
    provider_source=$cand
    break
  fi
done

# Dotfile managers may own a file or a parent directory through a symlink
# (the guard of 1788996284): preserve that layout rather than replacing the
# link with a copy or editing its target.
symlink_managed() {
  local path=$1
  while [[ $path != "$HOME" && $path != / ]]; do
    [[ -L $path ]] && return 0
    path=$(dirname "$path")
  done
  return 1
}

if [[ -d $nvim_config_dir ]] && { symlink_managed "$nvim_provider" || symlink_managed "$nvim_options"; }; then
  echo "Preserving symlink-managed Neovim config: $nvim_config_dir"
  echo "Review remote clipboard settings in your dotfile configuration manually."
elif [[ -d $nvim_config_dir && -n $provider_source ]]; then
  mkdir -p "$(dirname "$nvim_provider")"
  # Staged next to each target (same filesystem: an atomic rename).
  staged=$(mktemp "$nvim_provider.new.XXXXXX")
  trap 'rm -f -- "$staged"' EXIT
  install -m 0644 "$provider_source" "$staged"
  mv -fT -- "$staged" "$nvim_provider"

  if [[ -f $nvim_options ]] && ! grep -qF 'config.remote_clipboard' "$nvim_options"; then
    staged=$(mktemp "$nvim_options.new.XXXXXX")
    chmod --reference="$nvim_options" "$staged"
    {
      printf '%s\n' 'require("config.remote_clipboard").setup()'
      cat "$nvim_options"
    } >"$staged"
    mv -fT -- "$staged" "$nvim_options"
  fi
elif [[ -d $nvim_config_dir ]]; then
  echo "NixOS: remote_clipboard.lua source not found; skipping nvim provider install"
fi

# Appended through a symlink when its target is writable; a read-only one
# (a Home Manager store link) is left alone instead of failing every run.
tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -L $tmux_config && -f $tmux_config && ! -w $(readlink -f -- "$tmux_config") ]]; then
  echo "Preserving read-only symlinked tmux config: $tmux_config"
elif [[ -f $tmux_config ]] && ! grep -Eq '(^|[[:space:],"])\*:clipboard([[:space:]",]|$)' "$tmux_config"; then
  printf '\n# Enable OSC 52 clipboard forwarding for remote Neovim yanks.\nset -as terminal-features ",*:clipboard"\n' >>"$tmux_config"
fi
