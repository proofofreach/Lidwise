#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-probe-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/check-message.c" <<'C'
#include <IOKit/pwr_mgt/IOPM.h>
_Static_assert(kIOPMMessageClamshellStateChange == 0xe0034100u, "Clamshell message changed");
int main(void) { return 0; }
C
xcrun clang -fsyntax-only "$WORK/check-message.c"
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" "$ROOT/src/LidProbeModel.swift" \
  "$ROOT/tests/LidProbeTests.swift" -o "$WORK/probe-tests"
"$WORK/probe-tests"
# Compile the actual IOKit entry point; invalid arguments exit before measurement.
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" "$ROOT/src/LidProbeModel.swift" \
  "$ROOT/src/LidProbe.swift" -o "$WORK/lidwise-lid-probe"
if "$WORK/lidwise-lid-probe" --expect awake --seconds 0 > "$WORK/out" 2>&1; then
  echo 'Probe accepted an unbounded/invalid duration' >&2; exit 1
fi
grep -q 'usage:' "$WORK/out"
