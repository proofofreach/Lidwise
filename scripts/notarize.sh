#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"
case "$SIGNING_IDENTITY" in 'Developer ID Application:'*) ;; *) echo 'A Developer ID Application identity is required' >&2; exit 1 ;; esac
# Production candidates need a reproducible committed source, including tests/docs.
[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=normal)" ] || { echo 'Commit reviewed release inputs before notarizing.' >&2; exit 1; }
"$ROOT/scripts/check.sh"
mkdir -p "$ROOT/.build"
WORK=$(mktemp -d "$ROOT/.build/notarize.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
"$ROOT/scripts/build.sh"
APP="$ROOT/dist/Lidwise.app"
/usr/bin/ditto -c -k --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
RELEASE_MODE=production SKIP_BUILD=1 "$ROOT/scripts/package.sh"
