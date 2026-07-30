echo "Backfill tmux settings added before Omarchy quattro"

# NixOS adapter: keeps the upstream user-config edits (tmux.conf bindings,
# gsettings text scaling for the DX13260). The upstream hardware_packages
# block (sof-firmware, vulkan-intel/radeon/asahi via omarchy-pkg-add) is
# dropped — firmware and Vulkan drivers are declared natively by the NixOS
# configuration, and omarchy-state's reboot-required flag only exists for the
# pacman package install path.

tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]]; then
  sed -i 's/^set -g terminal-features\[3\] "xterm-kitty:extkeys"$/set -ag terminal-features "xterm-kitty:extkeys"/' "$tmux_config"

  if ! grep -q 'M-S-Enter' "$tmux_config"; then
    sed -i '/^# Pane Controls$/a\bind -n M-Enter split-window -v -c "#{pane_current_path}"\nbind -n M-S-Enter split-window -h -c "#{pane_current_path}"\nbind -n M-Escape kill-pane\n' "$tmux_config"
  fi

  omarchy-restart-tmux
fi

if omarchy-hw-match "DX13260"; then
  gsettings set org.gnome.desktop.interface text-scaling-factor 0.95
fi
