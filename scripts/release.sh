#!/usr/bin/env bash
# Builds, Developer ID-signs, notarizes and staples agent-manager, then
# packages dist/agent-manager.zip and dist/agent-manager.dmg for a GitHub
# release. Both open on any Mac without a Gatekeeper warning.
#
# One-time setup on the release Mac (app-specific password from
# account.apple.com, never committed):
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=<profile> ./scripts/release.sh
set -euo pipefail

cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

DIST="dist"
APP="$DIST/agent-manager.app"
ZIP="$DIST/agent-manager.zip"
DMG="$DIST/agent-manager.dmg"

./scripts/build.sh

# 1. Notarize the app itself and staple the ticket so it verifies offline.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"

# 2. Re-zip the stapled app for the download link the README uses.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# 3. Drag-to-Applications disk image, signed, notarized and stapled too.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "agent-manager" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

shasum -a 256 "$ZIP" "$DMG"
echo "Release artifacts ready in $DIST/"
