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
mkdir -p "$app/Contents/Frameworks"
ditto "$(dirname "$bin")/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
# Mobi is not sandboxed, so Sparkle needs none of its XPC services.
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/wubi86.txt "$app/Contents/Resources/"
cp -R Resources/*.lproj "$app/Contents/Resources/"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swift scripts/make_icons.swift "$tmp"
iconutil -c icns "$tmp/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp "$tmp/MenuIcon.pdf" "$app/Contents/Resources/"

identity="${SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
    sign=(codesign --force --sign -)
else
    sign=(codesign --force --options runtime --timestamp --sign "$identity")
fi
# Inside out: Sparkle's helpers, then Sparkle, then the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
"${sign[@]}" "$sparkle/Autoupdate"
"${sign[@]}" "$sparkle/Updater.app"
"${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
"${sign[@]}" "$app"
echo "Built $app"
