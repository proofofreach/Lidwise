#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/.build"
WORK=$(mktemp -d "$ROOT/.build/check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
for script in "$ROOT"/bin/lidwise* "$ROOT"/lib/lidwise/*.sh "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do /bin/bash -n "$script"; done
"$ROOT/scripts/build-helpers.sh"
for test_script in "$ROOT"/tests/*.sh; do
  [ "$(basename "$test_script")" = release-verifier-cases.sh ] && continue
  "$test_script"
done
DIST_DIR="$WORK/dist" "$ROOT/scripts/build.sh"
DIST_DIR="$WORK/dist" SKIP_BUILD=1 "$ROOT/scripts/package.sh"
"$ROOT/tests/release-verifier-cases.sh" "$WORK/dist/Lidwise-$(tr -d '[:space:]' < "$ROOT/VERSION")-macos-universal.zip"
if rg -n 'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' "$ROOT/bin" "$ROOT/src" "$ROOT/lib" "$ROOT/docs"; then
  echo 'Potential private key found' >&2; exit 1
fi
echo 'Local tests, universal build, and extracted development archive checks passed.'
