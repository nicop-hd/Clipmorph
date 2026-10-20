#!/usr/bin/env bash
# Builds Clipmorph.app into ./build (ad-hoc signed, for local use).
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary (Apple Silicon + Intel)
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Clipmorph"

APP=build/Clipmorph.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clipmorph"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png Resources/AboutHeader.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"
