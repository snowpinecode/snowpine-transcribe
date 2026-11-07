#!/bin/bash
# Downloads Sparkle's command line tools (sign_update and friends) once, checksum verified, and
# prints the folder that holds them. Same version as Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.10.1
SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
DIR=".build/sparkle-tools-$VERSION"
if [ ! -x "$DIR/bin/sign_update" ]; then
    mkdir -p "$DIR"
    curl -sSfL -o "$DIR/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
    echo "$SHA256  $DIR/sparkle.tar.xz" | shasum -a 256 -c - >&2
    tar -xf "$DIR/sparkle.tar.xz" -C "$DIR" bin/sign_update
    rm "$DIR/sparkle.tar.xz"
fi
echo "$PWD/$DIR/bin"
