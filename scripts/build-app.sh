#!/usr/bin/env bash
# Builds Clipmorph.app into ./build, signed for local use.
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
# Sign with a stable identity so macOS keeps the Accessibility permission across rebuilds
# (create it once with scripts/make-signing-cert.sh). Falls back to ad-hoc signing.
IDENTITY="${CODESIGN_IDENTITY:-Clipmorph Self-Signed}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: signing identity \"$IDENTITY\" not found, signing ad-hoc (Accessibility must be re-granted after each build)" >&2
    codesign --force --sign - "$APP"
fi

echo "Built $APP"
