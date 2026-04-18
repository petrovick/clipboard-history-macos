#!/usr/bin/env bash
set -euo pipefail

app_name="OptionVClipboard"
app_target="$HOME/Applications/OptionVClipboard.app"

if pgrep -x "$app_name" >/dev/null 2>&1; then
	osascript -e "tell application \"$app_name\" to quit" >/dev/null 2>&1 || true
	sleep 1
fi

rm -rf "$app_target"

printf 'Removed %s\n' "$app_target"
