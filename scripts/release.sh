#!/bin/bash
# Builds what a release ships, signed with Developer ID and notarized by Apple:
#   build/Mobi-<version>.pkg  the installer people download from wubi.app
#   build/Mobi-<version>.zip  the app alone, which Sparkle fetches to update an installed copy
# and adds the version to site/public/appcast.xml.
#
# Needs the "Developer ID Application" and "Developer ID Installer" certificates in the
# keychain, Sparkle's signing key (made once with generate_keys --account mobi) and
# notarization credentials saved once under a keychain profile:
#   xcrun notarytool store-credentials mobi-notary --apple-id <Apple ID> --team-id 7U5UR46DGH
# Set NOTARIZE=0 to stop after signing, e.g. to try the installer first. Without the Installer
# certificate the package is left unsigned, which is only good for trying it on this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:-Developer ID Application: BECOOL INC. (7U5UR46DGH)}"
installer="${INSTALLER_IDENTITY:-Developer ID Installer: BECOOL INC. (7U5UR46DGH)}"
profile="${NOTARY_PROFILE:-mobi-notary}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)"
pkg="build/Mobi-$version.pkg"
zip="build/Mobi-$version.zip"

SIGN_IDENTITY="$identity" ./scripts/build.sh
codesign --verify --strict --deep build/Mobi.app

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/root"
cp -R build/Mobi.app "$stage/root/"
# Into a staging folder, even where the system knows of a copy elsewhere; scripts/pkg/postinstall
# moves it on to the input methods folder of whoever is signed in.
pkgbuild --analyze --root "$stage/root" "$stage/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool false "$stage/components.plist"
pkgbuild --quiet --root "$stage/root" --component-plist "$stage/components.plist" \
    --scripts scripts/pkg --identifier com.becool.inputmethod.Mobi.pkg --version "$version" \
    --install-location "/Library/Application Support/Mobi" "$stage/Mobi.pkg"
cat > "$stage/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>末笔 $version</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <os-version min="13.0"/>
    <choices-outline><line choice="mobi"/></choices-outline>
    <choice id="mobi" title="末笔"><pkg-ref id="com.becool.inputmethod.Mobi.pkg"/></choice>
    <pkg-ref id="com.becool.inputmethod.Mobi.pkg" version="$version">Mobi.pkg</pkg-ref>
</installer-gui-script>
XML
# The keychain can hold a renewed certificate next to the old one under the same name; the
# one that runs out last signs.
newest() {
    security find-identity -v | grep -F "\"$1\"" | awk '{print $2}' | while read -r hash; do
        end="$(security find-certificate -a -Z -p -c "$1" | awk -v h="$hash" '
            /^SHA-1 hash:/ { keep = ($3 == h) } keep && /BEGIN/,/END/ { if (keep) print }' |
            openssl x509 -noout -enddate | cut -d= -f2)"
        echo "$(date -j -f '%b %e %T %Y %Z' "$end" +%s) $hash"
    done | sort -n | tail -1 | cut -d' ' -f2
}

rm -f "$pkg"
installerHash="$(newest "$installer")"
if [ -n "$installerHash" ]; then
    productbuild --quiet --distribution "$stage/distribution.xml" --package-path "$stage" --sign "$installerHash" --timestamp "$pkg"
else
    echo "No \"$installer\" certificate: $pkg is unsigned" >&2
    productbuild --quiet --distribution "$stage/distribution.xml" --package-path "$stage" "$pkg"
    NOTARIZE=0
fi

rm -f "$zip"
ditto -c -k --keepParent build/Mobi.app "$zip"

if [ "${NOTARIZE:-1}" != "0" ]; then
    xcrun notarytool submit "$pkg" --keychain-profile "$profile" --wait
    xcrun stapler staple "$pkg"
    spctl --assess --type install --verbose "$pkg"
    # The app inside the zip is notarized on its own, the zip itself cannot be stapled.
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
fi

# The appcast lists every release, newest first, with what changed as site/src/changelog.ts says it.
notes="$(node scripts/release-notes.mjs "$version")"
sparkle=".build/artifacts/sparkle/Sparkle/bin"
signature="$("$sparkle/sign_update" --account mobi "$zip")"
appcast="site/public/appcast.xml"
item="        <item>
            <title>$version</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[$notes]]></description>
            <enclosure url=\"https://github.com/becoolme/wubi.app/releases/download/v$version/Mobi-$version.zip\" $signature type=\"application/octet-stream\"/>
        </item>"
if grep -q "<sparkle:version>$build</sparkle:version>" "$appcast"; then
    echo "$appcast already lists build $build; left as it is" >&2
else
    ITEM="$item" perl -0pi -e 's|(<!-- releases -->\n)|$1$ENV{ITEM}\n|' "$appcast"
fi
echo "Built $pkg and $zip"
