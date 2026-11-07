#!/bin/bash
# Builds the zip people download: a universal app signed with SIGN_IDENTITY (ad-hoc without it), plus its SHA-256.
#   VERSION=0.2.0 scripts/package-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.2.0}"
UNIVERSAL=1 VERSION="$VERSION" scripts/build-app.sh
APP="build/Products.noindex/Snowpine Transcribe.app"
lipo -archs "$APP/Contents/MacOS/SnowpineTranscribe" | grep -q x86_64
lipo -archs "$APP/Contents/MacOS/SnowpineTranscribe" | grep -q arm64
"$APP/Contents/MacOS/SnowpineTranscribe" --launch-check
# A fixed name, so .../releases/latest/download/Snowpine-Transcribe.zip always gets the newest version.
ZIP="build/Snowpine-Transcribe.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd build && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "Packaged $ZIP ($VERSION)"
