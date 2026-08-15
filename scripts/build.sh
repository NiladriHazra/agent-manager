#!/usr/bin/env bash
# Builds agents-view.app from the SwiftPM package. Needs only Command Line
# Tools, no Xcode. Output: dist/agents-view.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
DIST="dist"
APP="$DIST/agents-view.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/AgentsView" "$APP/Contents/MacOS/AgentsView"

# SwiftPM emits target resources as a sibling bundle; Bundle.module finds it
# in the app's Resources directory at runtime.
if [ -d ".build/release/AgentsView_AgentsView.bundle" ]; then
  cp -R ".build/release/AgentsView_AgentsView.bundle" "$APP/Contents/Resources/"
fi

cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$DIST/AppIcon.icns" ]; then
  cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature: enough to run locally. Public distribution needs a
# Developer ID certificate plus notarization.
codesign --force --deep -s - "$APP"

echo "Built $APP"
