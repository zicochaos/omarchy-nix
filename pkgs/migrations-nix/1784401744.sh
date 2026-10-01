echo "Backfill tmux settings added before Omarchy quattro"

# NixOS adapter: keeps the upstream user-config edits (tmux.conf bindings,
# gsettings text scaling for the DX13260). The upstream hardware_packages
# block (sof-firmware, vulkan-intel/radeon/asahi via omarchy-pkg-add) is
# dropped — firmware and Vulkan drivers are declared natively by the NixOS
# configuration, and omarchy-state's reboot-required flag only exists for the
# pacman package install path.

# A symlinked tmux.conf (dotfile manager) is edited through the link, never
# replaced by a copy (plain sed -i would detach it); a read-only target (a
# Home Manager store link) is left alone instead of failing every run.
tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -L $tmux_config && -f $tmux_config && ! -w $(readlink -f -- "$tmux_config") ]]; then
  echo "Preserving read-only symlinked tmux config: $tmux_config"
elif [[ -f $tmux_config ]]; then
  sed -i --follow-symlinks 's/^set -g terminal-features\[3\] "xterm-kitty:extkeys"$/set -ag terminal-features "xterm-kitty:extkeys"/' "$tmux_config"

  if ! grep -q 'M-S-Enter' "$tmux_config"; then
    sed -i --follow-symlinks '/^# Pane Controls$/a\bind -n M-Enter split-window -v -c "#{pane_current_path}"\nbind -n M-S-Enter split-window -h -c "#{pane_current_path}"\nbind -n M-Escape kill-pane\n' "$tmux_config"
  fi

  omarchy-restart-tmux
fi

if omarchy-hw-match "DX13260"; then
  gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
fi
