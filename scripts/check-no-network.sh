#!/bin/bash
# Fails if the app gains a way to reach the network, the microphone or the camera, or any
# entitlement beyond the sandbox, user-chosen files, app-scoped bookmarks and what Sparkle needs
# for in-app updates. Only Sparkle's Downloader helper may use the network.
# These back the privacy promise in the README and SECURITY.md.
set -euo pipefail
cd "$(dirname "$0")/.."

ENT=Resources/SnowpineTranscribe.entitlements
fail=0

if grep -rnE "URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|import Network|WKWebView|CFSocket|CFStream|SocketPort|NSStream|getaddrinfo|AVCaptureDevice|AVAudioEngine|inputNode|SFSpeechRecognizer" Sources/; then
    echo "A networking, microphone or camera API appears in Sources/. Snowpine Transcribe promises none of these." >&2
    fail=1
fi

if [ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$ENT" 2>/dev/null)" != "true" ]; then
    echo "The App Sandbox entitlement is missing or not true." >&2
    fail=1
fi

# Sparkle (in-app updates) is used from one file only. Its own Downloader helper does the fetching.
if grep -rln "import Sparkle" Sources/ | grep -v "^Sources/SnowpineTranscribe/Updater.swift$"; then
    echo "Sparkle may only be imported in Sources/SnowpineTranscribe/Updater.swift." >&2
    fail=1
fi

# Exactly these entitlements: the sandbox, user-chosen files and app-scoped bookmarks, plus what Sparkle
# needs (loading its bundled framework, and the two local services -spks and -spki). Anything else
# (network, microphone, camera, wider file access) fails.
plutil -convert json -o - "$ENT" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
want = {
    "com.apple.security.app-sandbox": True,
    "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.files.bookmarks.app-scope": True,
    "com.apple.security.cs.disable-library-validation": True,
    "com.apple.security.temporary-exception.mach-lookup.global-name": ["__BUNDLE_ID__-spks", "__BUNDLE_ID__-spki"],
}
if d != want:
    sys.exit("Entitlements must be exactly %r\nFound: %r" % (want, d))
' || fail=1

if grep -q "com.apple.security.network" "$ENT"; then
    echo "The entitlements file grants network access." >&2
    fail=1
fi

[ $fail -eq 0 ] && echo "No-network check passed"
exit $fail
