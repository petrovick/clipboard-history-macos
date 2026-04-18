#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
app_source="$project_dir/.build/app/OptionVClipboard.app"
app_target="$HOME/Applications/OptionVClipboard.app"
app_name="OptionVClipboard"

if pgrep -x "$app_name" >/dev/null 2>&1; then
	osascript -e "tell application \"$app_name\" to quit" >/dev/null 2>&1 || true
	sleep 1
fi

"$script_dir/build-app.sh"

mkdir -p "$HOME/Applications"
rm -rf "$app_target"
ditto "$app_source" "$app_target"

printf 'Installed %s\n' "$app_target"
