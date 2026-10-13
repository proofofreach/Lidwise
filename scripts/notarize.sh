#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/Lidwise.app"
SUBMISSION="$ROOT/.build/notarization.zip"

: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application certificate name}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

SIGNING_IDENTITY="$SIGNING_IDENTITY" "$ROOT/scripts/build.sh"
/usr/bin/ditto -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
SKIP_BUILD=1 "$ROOT/scripts/package.sh"
