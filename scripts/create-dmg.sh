#!/usr/bin/env bash
# Packs ApplePointer.app into a compressed DMG with an Applications shortcut.
# Usage: ./scripts/create-dmg.sh <path/to/ApplePointer.app> <output.dmg>
set -euo pipefail
app="${1:?app path required}"
output="${2:?output dmg path required}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto --norsrc --noextattr --noqtn "$app" "$stage/$(basename "$app")"
xattr -cr "$stage/$(basename "$app")"
codesign --verify --deep --strict "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "ApplePointer" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$output" > /dev/null
echo "Created $output"
