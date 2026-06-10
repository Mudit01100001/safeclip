#!/bin/bash
# Builds, signs, notarizes, and packages SafeClip as a distributable .dmg
# (ROADMAP §6.6). A source push is NOT a release — binaries must be re-signed
# and re-notarized every time (CLAUDE.md caveat).
#
# One-time setup (requires a paid Apple Developer account):
#   1. Create a "Developer ID Application" certificate in Xcode / developer.apple.com
#   2. Store notarization credentials:
#        xcrun notarytool store-credentials safeclip-notary \
#          --apple-id YOUR_APPLE_ID --team-id YHK4D97KC4
#
# Usage:
#   DEVELOPER_ID="Developer ID Application: Mudit Ahlawat (YHK4D97KC4)" \
#   NOTARY_PROFILE=safeclip-notary Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Config/Info.plist)
DIST=dist
APP="$DIST/Build/Products/Release/SafeClip.app"
DMG="$DIST/SafeClip-$VERSION.dmg"

echo "── release build…"
rm -rf "$DIST"
xcodegen
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Release \
  -derivedDataPath "$DIST" build -quiet \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

echo "── verifying signature + hardened runtime…"
codesign --verify --strict --deep "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | head -5

echo "── packaging dmg…"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SafeClip $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "── notarizing (this waits for Apple)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

shasum -a 256 "$DMG"
echo "✅ $DMG ready — upload to GitHub Releases with the checksum above."
