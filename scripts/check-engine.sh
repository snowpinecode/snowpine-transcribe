#!/bin/bash
# End to end on this Mac with the real speech engine: speaks a known script with `say`, transcribes
# it, and checks the words. Needs the speech model, so it runs here rather than on GitHub's machines.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say -v Samantha -o "$TMP/check.aiff" "Thanks for joining today. The new booking page went live on Monday, and sign ups are already coming in."
OUT="$("$(swift build --show-bin-path)/SnowpineTranscribe" --locale en-US --transcribe "$TMP/check.aiff" 2>/dev/null)"
echo "$OUT"
for word in Thanks booking Monday coming; do
    grep -q "$word" <<<"$OUT" || { echo "Missing \"$word\" in the transcript." >&2; exit 1; }
done
grep -q "^\[0:0" <<<"$OUT" || { echo "The transcript has no times." >&2; exit 1; }
echo "Engine check passed"
