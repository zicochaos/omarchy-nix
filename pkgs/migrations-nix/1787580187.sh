echo "Refresh the Docker launcher for declarative Docker access"

# NixOS adapter: docker group membership belongs to the consumer's
# users.users.<name>.extraGroups. Keep only upstream's user launcher refresh.
dest="$HOME/.local/share/applications/Docker.desktop"
source="$OMARCHY_PATH/default/applications/Docker.desktop"
if [[ ! -f $source ]]; then
  echo "Docker launcher source not found: $source"
elif [[ -f $dest && ! -w $dest ]]; then
  echo "Preserving read-only Docker launcher: $dest"
elif [[ -f $dest ]]; then
  cp --no-preserve=mode "$source" "$dest"
fi
