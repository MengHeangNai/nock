#!/bin/bash
# Builds a GlassDock.app variant with the GlassDock Dock disabled by default.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/GlassDock-NoDock.app"
BUNDLE_ID="local.glassdock.nodock"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GlassDock "$APP/Contents/MacOS/GlassDock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName GlassDock-NoDock" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName GlassDock (No Dock)" "$APP/Contents/Info.plist"
defaults write "$BUNDLE_ID" enableDock -bool false
codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP with GlassDock Dock disabled by default"