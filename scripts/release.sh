#!/bin/bash
# Builds build/Mobi-<version>.dmg, signed with Developer ID and notarized by Apple.
#
# Needs the "Developer ID Application" certificate in the keychain and notarization credentials
# saved once under a keychain profile:
#   xcrun notarytool store-credentials mobi-notary --apple-id <Apple ID> --team-id 7U5UR46DGH
# Set NOTARIZE=0 to stop after signing, e.g. to try the disk image first.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:-Developer ID Application: BECOOL INC. (7U5UR46DGH)}"
profile="${NOTARY_PROFILE:-mobi-notary}"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
dmg="build/Mobi-$version.dmg"

SIGN_IDENTITY="$identity" ./scripts/build.sh
codesign --verify --strict --deep build/Mobi.app

# The disk image holds the app next to a link to /Library/Input Methods, to drag it onto.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R build/Mobi.app "$stage/"
ln -s "/Library/Input Methods" "$stage/输入法"
rm -f "$dmg"
hdiutil create -quiet -volname "末笔 $version" -srcfolder "$stage" -format UDZO -fs HFS+ "$dmg"
codesign --sign "$identity" --timestamp "$dmg"

if [ "${NOTARIZE:-1}" = "0" ]; then
    echo "Signed $dmg (not notarized)"
    exit 0
fi
xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
echo "Built $dmg"
