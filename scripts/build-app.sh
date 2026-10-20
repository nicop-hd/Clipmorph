#!/usr/bin/env bash
# Builds Clipmorph.app into ./build (ad-hoc signed, for local use).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Clipmorph.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Clipmorph "$APP/Contents/MacOS/Clipmorph"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png Resources/AboutHeader.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"
