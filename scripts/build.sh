#!/bin/bash
# Builds build/Mobi.app (末笔). Signed ad hoc unless SIGN_IDENTITY names a certificate,
# e.g. SIGN_IDENTITY="Developer ID Application: …", which also turns on the hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/Mobi"

app="build/Mobi.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Mobi"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/wubi86.txt "$app/Contents/Resources/"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swift scripts/make_icons.swift "$tmp"
iconutil -c icns "$tmp/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp "$tmp/MenuIcon.pdf" "$app/Contents/Resources/"

identity="${SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
echo "Built $app"
