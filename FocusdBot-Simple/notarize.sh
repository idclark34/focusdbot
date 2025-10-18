#!/bin/bash
set -euo pipefail

# Notarize and staple FocusdBot-Simple for distribution
# Prereqs:
# - Xcode CLT installed
# - Developer ID Application cert in keychain
# - notarytool keychain profile created (see README below)

# Config (override via environment if needed)
DEV_ID_DEFAULT="Developer ID Application: Ian Clark (C224CY39M8)"
DEV_ID="${DEV_ID:-$DEV_ID_DEFAULT}"
NOTARY_PROFILE="${NOTARY_PROFILE:-focusdbot-api}"
APP_NAME="FocusdBot-Simple.app"
SRC_DIR="dist"
APP_SRC="$SRC_DIR/$APP_NAME"
CLEAN_DIR="$SRC_DIR/_signed"
APP_CLEAN="$CLEAN_DIR/$APP_NAME"
ZIP="$SRC_DIR/FocusdBot-Simple.app.zip"
DMG="$SRC_DIR/FocusdBot-Simple.dmg"
VOLNAME="FocusdBot Simple"

printf "\n==> Rebuilding app bundle\n"
./create-app-bundle.sh

printf "\n==> Preparing clean copy (strip xattrs / FinderInfo)\n"
rm -rf "$CLEAN_DIR" && mkdir -p "$CLEAN_DIR"
cp -R -X "$APP_SRC" "$CLEAN_DIR/"
/usr/bin/find "$APP_CLEAN" -name '._*' -delete || true
/usr/bin/xattr -d -r com.apple.FinderInfo "$APP_CLEAN" 2>/dev/null || true
/usr/bin/xattr -d -r com.apple.ResourceFork "$APP_CLEAN" 2>/dev/null || true
/usr/bin/xattr -d com.apple.FinderInfo "$APP_CLEAN" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$APP_CLEAN" 2>/dev/null || true
xattr -cr "$APP_CLEAN" || true

printf "\n==> Codesigning with hardened runtime\n"
codesign --deep --force --options runtime --timestamp --sign "$DEV_ID" "$APP_CLEAN"

/usr/bin/xattr -d com.apple.FinderInfo "$APP_CLEAN" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$APP_CLEAN" 2>/dev/null || true

printf "\n==> Verifying signature\n"
codesign --verify --deep --strict --verbose=2 "$APP_CLEAN"

printf "\n==> Creating ZIP for notarization\n"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_CLEAN" "$ZIP"

printf "\n==> Submitting APP to Apple Notary Service\n"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

printf "\n==> Stapling ticket to app\n"
xcrun stapler staple "$APP_CLEAN"

printf "\n==> Creating DMG\n"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$APP_CLEAN" -ov -format UDZO "$DMG"

printf "\n==> Notarizing DMG (required before stapling)\n"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

printf "\n==> Stapling ticket to DMG\n"
xcrun stapler staple "$DMG"

printf "\n==> Gatekeeper check\n"
spctl -a -vvv --type execute "$APP_CLEAN" || true

printf "\n✅ Done. Deliverable: %s\n" "$DMG"

# README (one-time):
# xcrun notarytool store-credentials focusdbot \
#   --apple-id YOUR_APPLE_ID --team-id C224CY39M8 --password APP_SPECIFIC_PASSWORD
