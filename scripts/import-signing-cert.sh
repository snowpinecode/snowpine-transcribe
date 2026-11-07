#!/bin/bash
# Imports the release signing certificate (a .p12) into a throwaway keychain and prints that
# keychain's path, for SIGN_KEYCHAIN. The login keychain is never touched.
#   SIGN_KEYCHAIN=$(scripts/import-signing-cert.sh <cert.p12> <password-file>)
# In CI the .p12 and its password come from repository secrets and the keychain lives in RUNNER_TEMP.
set -euo pipefail
P12="$1"
PASSWORD="$(cat "$2")"
DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="$DIR/app-signing-$$.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
# Any failure after this point removes the keychain, so no private key is left behind.
trap 'security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true' ERR
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security set-keychain-settings -lut 3600 "$KEYCHAIN" >&2
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >&2
security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >&2
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
security find-identity -p codesigning "$KEYCHAIN" | grep -q "1 identities found" \
    || { security delete-keychain "$KEYCHAIN"; echo "The certificate didn't import." >&2; exit 1; }
# On a CI runner, codesign looks for the private key through the keychain search list, so the throwaway
# keychain goes on it there. On a person's Mac the search list is left alone (codesign finds it via --keychain).
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # shellcheck disable=SC2046
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"') >&2
fi
trap - ERR
echo "$KEYCHAIN"
