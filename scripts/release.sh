#!/usr/bin/env bash
# Builds, zips and publishes a GitHub release for the version in Resources/Info.plist.
# Installed copies pick it up through Check for Updates, so the build must be signed with the
# same certificate as before (scripts/make-signing-cert.sh), or their updates will be rejected.
#
#   scripts/release.sh [notes-file]
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:-Clipmorph Self-Signed}"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "error: signing identity \"$IDENTITY\" not found; releases must not be ad-hoc signed" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: release $TAG already exists; bump CFBundleShortVersionString and CFBundleVersion first" >&2
    exit 1
fi

./scripts/build-app.sh
codesign --verify --strict --deep build/Clipmorph.app

rm -f build/Clipmorph.zip
ditto -c -k --keepParent build/Clipmorph.app build/Clipmorph.zip

NOTES_ARGS=(--generate-notes)
if [[ $# -ge 1 ]]; then NOTES_ARGS=(--notes-file "$1"); fi
gh release create "$TAG" build/Clipmorph.zip --title "Clipmorph $VERSION" "${NOTES_ARGS[@]}"
echo "Published $TAG"
