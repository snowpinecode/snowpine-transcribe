#!/bin/bash
# Copies Sparkle.framework into an app bundle and signs its parts inside out, as Sparkle's
# sandboxing guide describes: Installer, Downloader, Autoupdate, Updater.app, then the framework.
# The services keep Sparkle's own setup (no extra entitlements): giving the shared Downloader a sandbox
# would need a Sparkle build with an app-specific service id. The app is signed afterwards by the caller.
#   scripts/embed-sparkle.sh <App.app> <identity> [keychain]
# Reusable: nothing in here is specific to one app.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
IDENTITY="$2"
KEYCHAIN="${3:-}"

FRAMEWORK=$(find .build/artifacts -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' -maxdepth 6 -type d | head -1)
[ -n "$FRAMEWORK" ] || { echo "Sparkle.framework not found; run swift package resolve" >&2; exit 1; }

mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# The executable finds the framework through this rpath.
BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
otool -l "$BIN" | grep -q "@executable_path/../Frameworks" || install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"

SIGN=(codesign --force --options runtime --timestamp=none --sign "$IDENTITY")
if [ -n "$KEYCHAIN" ]; then SIGN+=(--keychain "$KEYCHAIN"); fi
B="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$B/XPCServices/Installer.xpc"
"${SIGN[@]}" "$B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$B/Autoupdate"
"${SIGN[@]}" "$B/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
