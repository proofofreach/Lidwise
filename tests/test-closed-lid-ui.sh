#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/closedlid-ui-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/src/ProcessRunner.swift" \
  "$ROOT/src/ClosedLidUIModel.swift" \
  "$ROOT/tests/ClosedLidUIModelTests.swift" \
  -o "$OUT/ClosedLidUIModelTests"

"$OUT/ClosedLidUIModelTests"

# Compile actual production view definitions with an isolated top-level fixture.
sed '/^#if CARD_PREVIEW/,$d' "$ROOT/src/ClosedLidAwake.swift" > "$OUT/main.swift"
cat "$ROOT/tests/ClosedLidUILayoutTests.swift" >> "$OUT/main.swift"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework Carbon \
  "$OUT/main.swift" "$ROOT/src/ProcessRunner.swift" "$ROOT/src/ClosedLidUIModel.swift" -o "$OUT/layout-tests"
"$OUT/layout-tests"
