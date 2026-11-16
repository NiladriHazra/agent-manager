#!/usr/bin/env bash
# Builds agent-manager.app from the SwiftPM package as a universal binary
# (Apple Silicon + Intel). Needs only Command Line Tools, no Xcode.
#
# Output: dist/agent-manager.app
#
# Signing:
#   SIGN_IDENTITY unset  -> ad-hoc signature (runs on this Mac only)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#                        -> Developer ID signature with hardened runtime and a
#                           secure timestamp, ready for scripts/release.sh to
#                           notarize.
set -euo pipefail

cd "$(dirname "$0")/.."
DIST="dist"
APP="$DIST/agent-manager.app"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AgentManager" "$APP/Contents/MacOS/AgentManager"

# SwiftPM emits target resources as a sibling bundle; Bundle.module finds it
# in the app's Resources directory at runtime.
if [ -d "$BIN/AgentManager_AgentManager.bundle" ]; then
  cp -R "$BIN/AgentManager_AgentManager.bundle" "$APP/Contents/Resources/"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Committed to the repo so a clean checkout builds with the real icon.
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # Hardened runtime + timestamp are both required for notarization.
  codesign --force --options runtime --timestamp \
    --entitlements "Resources/AgentManager.entitlements" \
    -s "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  codesign --force -s - "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/AgentManager"))"
