#!/bin/bash
# Fails if the app code gains a way to reach the network. These back the privacy promise in the README.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
if grep -rnE "URLSession|URLRequest|NSURLConnection|NWConnection|NWListener|import Network|WKWebView|CFSocket|CFStream|SocketPort" Sources; then
    echo "A networking API appears in Sources/. Snowpine Transcribe promises no network access." >&2
    fail=1
fi
if grep -q "com.apple.security.network" Resources/SnowpineTranscribe.entitlements; then
    echo "The entitlements file grants network access." >&2
    fail=1
fi
if grep -q "com.apple.security.device" Resources/SnowpineTranscribe.entitlements; then
    echo "The app works from files and must not ask for the microphone or camera." >&2
    fail=1
fi
if [ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" Resources/SnowpineTranscribe.entitlements 2>/dev/null)" != "true" ]; then
    echo "The App Sandbox entitlement is missing or not true." >&2
    fail=1
fi
[ $fail -eq 0 ] && echo "No-network check passed"
exit $fail
