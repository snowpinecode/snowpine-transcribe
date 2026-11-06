#!/bin/bash
# Builds the zip people download: a universal, ad-hoc signed app, plus its SHA-256.
#   VERSION=0.1.0 scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
UNIVERSAL=1 VERSION="$VERSION" scripts/build-app.sh
APP="build/Snowpine Transcribe.app"
lipo -archs "$APP/Contents/MacOS/SnowpineTranscribe" | grep -q x86_64
lipo -archs "$APP/Contents/MacOS/SnowpineTranscribe" | grep -q arm64
"$APP/Contents/MacOS/SnowpineTranscribe" --launch-check
ZIP="build/Snowpine-Transcribe-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
# A copy with no version in its name, so the page's Download button always gets the latest release.
cp "$ZIP" build/Snowpine-Transcribe.zip
echo "Packaged $ZIP"
