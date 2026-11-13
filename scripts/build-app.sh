#!/bin/bash
# Builds GlassDock.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/GlassDock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GlassDock "$APP/Contents/MacOS/GlassDock"
cp .build/release/libGlassDockMediaRemote.dylib "$APP/Contents/MacOS/libGlassDockMediaRemote.dylib"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp assets/icon.png "$APP/Contents/Resources/icon.png"
codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"
