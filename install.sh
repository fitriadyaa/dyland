#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
npm ci --prefix plugin --ignore-scripts
/bin/zsh ./build.sh
app="$HOME/Applications/Dyland.app"
plugin="$HOME/.config/opencode/plugins/dyland"
if [[ -e "$app" || -e "$plugin" ]]; then
    print -u2 -- "Install stopped: $app or $plugin already exists. Back up or remove old Dyland installation first."
    exit 1
fi
mkdir -p "$HOME/Applications" "${plugin:h}"
cp -R dist/Dyland.app "$app"
ln -s "$PWD/plugin" "$plugin"
open "$app"
print -r -- "Installed $app"
print -r -- "Plugin linked: $plugin"
print -r -- "OpenCode reloads plugin configuration automatically. Do not restart service while agents are working."
