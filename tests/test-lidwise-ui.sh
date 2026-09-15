#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d /tmp/lidwise-ui-tests.XXXXXX)
trap 'rm -rf "$OUT"' EXIT

xcrun swiftc \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework AppKit \
  "$ROOT/src/ProcessRunner.swift" \
  "$ROOT/src/LidwiseUIModel.swift" \
  "$ROOT/src/LidwiseFeatureUI.swift" \
  "$ROOT/tests/LidwiseUIModelTests.swift" \
  -o "$OUT/LidwiseUIModelTests"

"$OUT/LidwiseUIModelTests"

# Compile actual production view definitions with an isolated top-level fixture.
sed '/^#if CARD_PREVIEW/,$d' "$ROOT/src/Lidwise.swift" > "$OUT/main.swift"
cat "$ROOT/tests/LidwiseUILayoutTests.swift" >> "$OUT/main.swift"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework Carbon \
  "$OUT/main.swift" "$ROOT/src/ProcessRunner.swift" "$ROOT/src/LidwiseUIModel.swift" \
  "$ROOT/src/LidwiseFeatureUI.swift" -o "$OUT/layout-tests"
"$OUT/layout-tests"
