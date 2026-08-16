#!/usr/bin/env bash
# Builds agent-manager.app from the SwiftPM package. Needs only Command Line
# Tools, no Xcode. Output: dist/agent-manager.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
DIST="dist"
APP="$DIST/agent-manager.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/AgentManager" "$APP/Contents/MacOS/AgentManager"

# SwiftPM emits target resources as a sibling bundle; Bundle.module finds it
# in the app's Resources directory at runtime.
if [ -d ".build/release/AgentManager_AgentManager.bundle" ]; then
  cp -R ".build/release/AgentManager_AgentManager.bundle" "$APP/Contents/Resources/"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"

# Committed to the repo so a clean checkout builds with the real icon; the
# old copy lived only in dist/ and was lost on every clean.
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature: enough to run locally. Public distribution needs a
# Developer ID certificate plus notarization.
codesign --force --deep -s - "$APP"

echo "Built $APP"
