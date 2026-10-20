#!/usr/bin/env bash
# Regenerates the app icon (.icns) and menu-bar template PNGs from Resources/Icon/*.svg.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -O scripts/render-svg.swift -o "$TMP/render-svg"

ICONSET="$TMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
    "$TMP/render-svg" Resources/Icon/AppIcon.svg "$ICONSET/icon_${size}x${size}.png" "$size"
    "$TMP/render-svg" Resources/Icon/AppIcon.svg "$ICONSET/icon_${size}x${size}@2x.png" "$((size * 2))"
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

"$TMP/render-svg" Resources/Icon/MenuBarIcon.svg Resources/MenuBarIconTemplate.png 18
"$TMP/render-svg" Resources/Icon/MenuBarIcon.svg Resources/MenuBarIconTemplate@2x.png 36

echo "Icons written to Resources/"
