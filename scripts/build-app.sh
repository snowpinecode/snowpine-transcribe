#!/bin/bash
# Builds build/Products.noindex/Snowpine Transcribe.app: a sandboxed Mac app with Sparkle for in-app updates, signed with
# SIGN_IDENTITY (the release certificate, from SIGN_KEYCHAIN when set) or ad-hoc when that is not set.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build, then move it to ~/Applications
# BUNDLE_ID and VERSION can be overridden from the environment. UNIVERSAL=1 builds for Apple silicon and Intel.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.snowpinecode.transcribe}"
VERSION="${VERSION:-0.2.1}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

ARCHS=()
if [ "${UNIVERSAL:-}" = "1" ]; then ARCHS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/SnowpineTranscribe"

# Spotlight skips any folder whose name ends in .noindex, so a build never shows up as a second
# Snowpine Transcribe next to the installed one.
APP="build/Products.noindex/Snowpine Transcribe.app"
rm -rf "build/Snowpine Transcribe.app" "$APP"  # build/Snowpine Transcribe.app: where older builds went
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnowpineTranscribe"
# The brand fonts (SIL Open Font License) travel with the app.
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
# Sparkle's license travels with its framework.
cp Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/"
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

# Signing. SIGN_IDENTITY is the release certificate (CI imports it into SIGN_KEYCHAIN, a throwaway
# keychain; the login keychain is never used); without it the build is ad-hoc signed, which is fine for
# testing. To share a download that opens without warnings, sign with a Developer ID and notarize instead.
IDENTITY="${SIGN_IDENTITY:--}"
KEYCHAIN_ARGS=()
if [ -n "${SIGN_KEYCHAIN:-}" ]; then KEYCHAIN_ARGS=(--keychain "$SIGN_KEYCHAIN"); fi

# Sparkle (in-app updates) goes in first and is signed inside out.
scripts/embed-sparkle.sh "$APP" "$IDENTITY" "${SIGN_KEYCHAIN:-}"

# The app's entitlements, with the bundle id filled in for Sparkle's local service names, and the
# hardened runtime.
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" Resources/SnowpineTranscribe.entitlements > build/SnowpineTranscribe.entitlements
codesign --force --options runtime --timestamp=none --entitlements build/SnowpineTranscribe.entitlements \
    --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP"
codesign --verify --strict --deep "$APP"

# Check the entitlements actually signed into the app: exactly the sandbox, user-chosen files and
# app-scoped bookmarks, plus Sparkle's framework loading and its two local service names.
# No network, microphone or camera.
SIGNED="build/signed-entitlements.plist"
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$SIGNED"
/usr/bin/python3 - "$SIGNED" "$BUNDLE_ID" <<'PY2'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb")); bid = sys.argv[2]
want = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.cs.disable-library-validation": True,
    "com.apple.security.temporary-exception.mach-lookup.global-name": [bid + "-spks", bid + "-spki"],
}
if d != want:
    sys.exit("The signed app's entitlements are not exactly the expected set: %r" % d)
PY2
# Sparkle's helpers keep Sparkle's own setup: no entitlements at all, on every architecture.
for part in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app; do
    BINPATH="$APP/Contents/Frameworks/Sparkle.framework/Versions/B/$part"
    for arch in $(lipo -archs "$(find "$BINPATH/Contents/MacOS" -type f | head -1)"); do
        if codesign -d --entitlements - --xml --arch "$arch" "$BINPATH" 2>/dev/null | grep -q "<key>"; then
            echo "Sparkle's $part ($arch) must carry no entitlements." >&2
            exit 1
        fi
    done
done
for arch in $(lipo -archs "$APP/Contents/MacOS/SnowpineTranscribe"); do
    codesign -d --entitlements - --xml --arch "$arch" "$APP" 2>/dev/null | cmp -s - "$SIGNED" \
        || { echo "The app's entitlements differ on $arch." >&2; exit 1; }
done
echo "Built $APP ($VERSION, $BUNDLE_ID)"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Snowpine Transcribe.app"
    # Move rather than copy, so Spotlight finds one Snowpine Transcribe, not a second one in build/.
    mv "$APP" "$HOME/Applications/"
    echo "Installed ~/Applications/Snowpine Transcribe.app"
fi
