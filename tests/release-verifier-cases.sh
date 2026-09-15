#!/bin/bash
# Called after packaging by check.sh; mutate only temporary copies of that archive.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[ "$#" -eq 1 ] || { echo 'usage: release-verifier-cases.sh candidate.zip' >&2; exit 2; }
ORIGINAL=$1
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-release-tests.XXXXXX")
cleanup() {
  local result=$?
  if [ "$result" -ne 0 ] && [ -f "$WORK/output" ]; then cat "$WORK/output" >&2; fi
  rm -rf "$WORK"
  exit "$result"
}
trap cleanup EXIT
reset_archive() {
  rm -rf "$WORK/extracted"
  mkdir "$WORK/extracted"
  /usr/bin/ditto -x -k "$ORIGINAL" "$WORK/extracted"
  roots=("$WORK/extracted"/*)
  PACKAGE=${roots[0]}
  APP="$PACKAGE/Lidwise.app"
}
reject_archive() {
  rm -f "$WORK/candidate.zip"
  (cd "$WORK/extracted" && /usr/bin/zip -qry -X "$WORK/candidate.zip" "$(basename "$PACKAGE")")
  (cd "$WORK" && /usr/bin/shasum -a 256 candidate.zip > candidate.zip.sha256)
  if ARCHS=arm64 "$ROOT/scripts/verify-release.sh" community "$WORK/candidate.zip" > "$WORK/output" 2>&1; then
    echo "Verifier accepted invalid archive: $1" >&2; exit 1
  fi
}
reset_archive
printf hidden > "$WORK/extracted/.payload"
(cd "$WORK/extracted" && /usr/bin/zip -qry -X "$WORK/hidden.zip" .)
(cd "$WORK" && /usr/bin/shasum -a 256 hidden.zip > hidden.zip.sha256)
if "$ROOT/scripts/verify-release.sh" community "$WORK/hidden.zip" > "$WORK/output" 2>&1; then
  echo 'Verifier accepted a hidden sibling outside the package root' >&2; exit 1
fi
reset_archive
cp /usr/bin/true "$PACKAGE/unexpected-tool"
reject_archive 'extra executable'
grep -q 'Unexpected archive file' "$WORK/output"
reset_archive
rm "$APP/Contents/Helpers/lidwise-agent-scan-core"
/usr/bin/codesign --force --sign - "$APP" 2>/dev/null
reject_archive 'missing scanner'
reset_archive
rm "$APP/Contents/Helpers/lidwise-lid-probe"
/usr/bin/codesign --force --sign - "$APP" 2>/dev/null
reject_archive 'missing lid measurement helper'
reset_archive
mv "$APP/Contents/Helpers/lidwise-lid-probe" "$APP/Contents/Helpers/unexpected-probe"
printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/Helpers/lidwise-lid-probe"
chmod 755 "$APP/Contents/Helpers/lidwise-lid-probe"
/usr/bin/codesign --force --sign - "$APP/Contents/Helpers/lidwise-lid-probe" 2>/dev/null
/usr/bin/codesign --force --sign - "$APP" 2>/dev/null
reject_archive 'shell stub plus misplaced native probe'
grep -q 'Expected native executable missing: Contents/Helpers/lidwise-lid-probe' "$WORK/output"
reset_archive
cp "$APP/Contents/Helpers/lidwise-lid-probe" "$APP/Contents/Helpers/unexpected-probe"
/usr/bin/codesign --force --sign - "$APP" 2>/dev/null
reject_archive 'unexpected nested native executable'
grep -q 'Unexpected native executable' "$WORK/output"
reset_archive
/usr/bin/lipo "$APP/Contents/MacOS/Lidwise" -thin arm64 -output "$WORK/thin"
cp "$WORK/thin" "$APP/Contents/MacOS/Lidwise"
/usr/bin/codesign --force --sign - "$APP" 2>/dev/null
reject_archive 'single-architecture universal archive'
grep -q 'Missing x86_64' "$WORK/output"
reset_archive
printf '\nStale document\n' >> "$PACKAGE/docs/CLI.md"
reject_archive 'stale packaged documentation'
# Package rejection leaves the previous canonical archive and checksum untouched.
reset_archive
mkdir "$WORK/destination"
name=$(basename "$ORIGINAL")
cp "$ORIGINAL" "$WORK/destination/$name"
cp "$ORIGINAL.sha256" "$WORK/destination/$name.sha256"
/usr/bin/ditto "$APP" "$WORK/destination/Lidwise.app"
rm "$WORK/destination/Lidwise.app/Contents/Helpers/lidwise-agent-scan-core"
/usr/bin/codesign --force --sign - "$WORK/destination/Lidwise.app" 2>/dev/null
if DIST_DIR="$WORK/destination" SKIP_BUILD=1 RELEASE_MODE=community "$ROOT/scripts/package.sh" > "$WORK/output" 2>&1; then
  echo 'Packager accepted missing scanner' >&2; exit 1
fi
cmp "$ORIGINAL" "$WORK/destination/$name"
cmp "$ORIGINAL.sha256" "$WORK/destination/$name.sha256"
echo 'archive rejects hidden/unexpected code, missing scanner, thin architecture and stale guides; rejected package preserves prior candidate: ok'
