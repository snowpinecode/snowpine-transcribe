#!/bin/bash
# Runs every check that needs no speech model: unit tests, the no-network check, and the render check.
set -euo pipefail
cd "$(dirname "$0")/.."

# With only the Command Line Tools installed (no Xcode), SwiftPM may not find the
# Swift Testing macro plugin; point it there explicitly when it exists.
EXTRA=()
PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [ -d "$PLUGINS" ] && ! xcode-select -p | grep -q Xcode.app; then
    EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")
fi

swift test ${EXTRA[@]+"${EXTRA[@]}"}
scripts/check-no-network.sh
swift build
"$(swift build --show-bin-path)/SnowpineTranscribe" --smoke-test "${TMPDIR:-/tmp}/snowpine-transcribe-smoke"
