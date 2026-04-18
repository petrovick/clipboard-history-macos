#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
build_dir="$project_dir/.build"
release_bin="$build_dir/release/OptionVClipboard"
app_dir="$build_dir/app/OptionVClipboard.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
info_plist_src="$project_dir/Resources/Info.plist"
info_plist_dst="$contents_dir/Info.plist"

swift build -c release --package-path "$project_dir"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$release_bin" "$macos_dir/OptionVClipboard"
cp "$info_plist_src" "$info_plist_dst"
chmod 755 "$macos_dir/OptionVClipboard"

codesign --force --deep --sign - --timestamp=none "$app_dir"

printf 'Built %s\n' "$app_dir"
