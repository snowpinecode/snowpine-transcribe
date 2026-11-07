#!/bin/bash
# Writes build/appcast.xml: the update feed Sparkle reads, with one item for this release.
# The download is signed with the EdDSA private key (from SPARKLE_ED_PRIVATE_KEY, or a file).
#   SPARKLE_ED_PRIVATE_KEY=... scripts/make-appcast.sh <App> <owner/repo> <version> <build> <min macOS> <zip>
#   scripts/make-appcast.sh ... <zip> <private-key-file>
# Reusable: nothing in here is specific to one app.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="$1"; REPO="$2"; VERSION="$3"; BUILD="$4"; MINOS="$5"; ZIP="$6"; KEYFILE="${7:-}"

SIGN_UPDATE="${SIGN_UPDATE:-$(scripts/sparkle-tools.sh)/sign_update}"
if [ -n "$KEYFILE" ]; then
    SIG=$("$SIGN_UPDATE" --ed-key-file "$KEYFILE" -p "$ZIP")
else
    SIG=$(printf '%s' "${SPARKLE_ED_PRIVATE_KEY:?set SPARKLE_ED_PRIVATE_KEY or pass a key file}" | "$SIGN_UPDATE" --ed-key-file - -p "$ZIP")
fi
LENGTH=$(stat -f%z "$ZIP")
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
BASE="https://github.com/$REPO/releases"

cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <item>
      <title>$NAME $VERSION</title>
      <pubDate>$DATE</pubDate>
      <link>$BASE/tag/v$VERSION</link>
      <sparkle:releaseNotesLink>$BASE/tag/v$VERSION</sparkle:releaseNotesLink>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <enclosure url="$BASE/download/v$VERSION/$(basename "$ZIP")" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$SIG"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote build/appcast.xml ($NAME $VERSION, build $BUILD)"
