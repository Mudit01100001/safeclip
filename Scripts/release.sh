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
ARCHIVE="$DIST/SafeClip.xcarchive"
DMG="$DIST/SafeClip-$VERSION.dmg"

echo "── release archive…"
rm -rf "$DIST"
xcodegen
# NOTE: `archive` (not `build`) — plain `build` always injects the
# com.apple.security.get-task-allow debug entitlement (so Xcode can attach a
# debugger) regardless of configuration or signing identity, which fails
# notarization outright. `archive` + `-exportArchive` is the distribution path.
xcodebuild -project SafeClip.xcodeproj -scheme SafeClip -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

echo "── exporting for Developer ID distribution…"
EXPORT_OPTIONS=$(mktemp)
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>YHK4D97KC4</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DIST/Export" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -quiet
rm -f "$EXPORT_OPTIONS"
APP="$DIST/Export/SafeClip.app"

echo "── deep-signing Sparkle's bundled helper binaries…"
# Sparkle.framework ships pre-built nested code (Autoupdate, Updater.app, two
# XPC services) that Xcode's own signing does not recurse into — each must be
# re-signed with the Developer ID identity individually (innermost first),
# then the framework, then the outer app (whose seal the framework re-sign
# just invalidated).
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
find "$SPARKLE_FW/Versions" -type d -name "*.xpc" -exec \
  codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime {} \;
find "$SPARKLE_FW/Versions" -type f -name "Autoupdate" -exec \
  codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime {} \;
find "$SPARKLE_FW/Versions" -type d -name "Updater.app" -exec \
  codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime {} \;
codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime "$SPARKLE_FW"
codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime \
  --entitlements Config/SafeClip.entitlements "$APP"

echo "── verifying signature + hardened runtime…"
codesign --verify --strict --deep "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | head -5

echo "── packaging styled dmg…"
# Build a read-write dmg first so Finder can lay out the icon view (app on the
# left, Applications alias on the right) over a custom background, then convert
# it to the compressed read-only UDZO that ships. The background PNG is
# committed (Scripts/assets/dmg-background@2x.png); regenerate it with
# Scripts/dmg_background.swift if you change the window geometry below — the icon
# centres and window content size MUST stay in lockstep with that script.
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp Scripts/assets/dmg-background@2x.png "$STAGING/.background/background.png"

VOLNAME="SafeClip $VERSION"
RW_DMG="$DIST/SafeClip-rw.dmg"
rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ \
  -format UDRW -ov "$RW_DMG"
rm -rf "$STAGING"

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
  | grep -E '^/dev/' | head -1 | awk '{print $1}')
sleep 2  # let Finder mount before scripting it

# NOTE (owner machine, one-time): the first run of this Finder step triggers a
# "Terminal wants to control Finder" Automation consent prompt — allow it.
# Window chrome height isn't scriptable-exact; if the background doesn't sit
# flush on the first styled release, nudge the window height in `bounds` below
# (and Scripts/dmg_background.swift's H) and re-run.
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.png"
    set position of item "SafeClip.app" of container window to {160, 200}
    set position of item "Applications" of container window to {480, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync  # flush the .DS_Store layout to the image before detaching
hdiutil detach "$DEVICE"
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

echo "── notarizing (this waits for Apple)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

shasum -a 256 "$DMG"

echo "── signing for Sparkle appcast…"
SIG_ATTRS=$(Scripts/sparkle_sign.swift "$DMG")
echo "$SIG_ATTRS"

echo "✅ $DMG ready — upload it to safeclip.app, then add an <item> to"
echo "   appcast.xml (safeclip-web/public/appcast.xml) with:"
echo "     <enclosure url=\"https://safeclip.app/downloads/SafeClip-$VERSION.dmg\""
echo "       sparkle:version=\"\$(cat Config/Info.plist build number)\""
echo "       sparkle:shortVersionString=\"$VERSION\""
echo "       $SIG_ATTRS"
echo "       type=\"application/octet-stream\" />"
