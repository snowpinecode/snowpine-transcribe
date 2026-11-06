#!/bin/bash
# Builds build/Snowpine Transcribe.app: a sandboxed, ad-hoc signed Mac app.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build, then move it to ~/Applications
# BUNDLE_ID and VERSION can be overridden from the environment. UNIVERSAL=1 builds for Apple silicon and Intel.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.snowpinecode.transcribe}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

ARCHS=()
if [ "${UNIVERSAL:-}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/SnowpineTranscribe"

APP="build/Snowpine Transcribe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnowpineTranscribe"
# The brand fonts (SIL Open Font License) travel with the app.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
# App icon: Resources/AppIcon.png (1024 x 1024) becomes AppIcon.icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature with the hardened runtime and the sandbox entitlements.
# To share a download that opens without warnings, sign with a Developer ID and notarize instead.
codesign --force --options runtime --entitlements Resources/SnowpineTranscribe.entitlements --sign - "$APP"
codesign --verify --strict "$APP"

# Check the entitlements actually signed into the app: sandbox on, no network.
SIGNED="build/signed-entitlements.plist"
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$SIGNED"
if [ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$SIGNED" 2>/dev/null)" != "true" ] \
    || grep -q "com.apple.security.network" "$SIGNED"; then
    echo "The signed app must have the App Sandbox on and no network entitlement." >&2
    exit 1
fi
echo "Built $APP ($VERSION, $BUNDLE_ID)"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Snowpine Transcribe.app"
    # Move rather than copy, so Spotlight finds one Snowpine Transcribe, not a second one in build/.
    mv "$APP" "$HOME/Applications/"
    echo "Installed ~/Applications/Snowpine Transcribe.app"
fi
