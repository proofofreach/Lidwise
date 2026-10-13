#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
NAME="Lidwise-$VERSION-macos-universal"
STAGE="$ROOT/.build/release/$NAME"
ZIP="$ROOT/dist/$NAME.zip"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  "$ROOT/scripts/build.sh"
fi
[ -d "$ROOT/dist/Lidwise.app" ] || {
  echo "Missing built app. Run scripts/build.sh first." >&2
  exit 1
}
rm -rf "$STAGE" "$ZIP" "$ZIP.sha256"
mkdir -p "$STAGE"
/usr/bin/ditto "$ROOT/dist/Lidwise.app" "$STAGE/Lidwise.app"
cp "$ROOT/scripts/install.sh" "$STAGE/install.sh"
cp "$ROOT/scripts/uninstall.sh" "$STAGE/uninstall.sh"
cp "$ROOT/README.md" "$ROOT/SECURITY.md" "$ROOT/RELEASE_CHECKLIST.md" \
  "$ROOT/CHANGELOG.md" "$ROOT/LICENSE" "$STAGE/"
mkdir -p "$STAGE/assets"
cp "$ROOT/assets/app-icon.png" "$STAGE/assets/"
cp "$ROOT/assets/lidwise-hero.png" "$STAGE/assets/"
chmod 0755 "$STAGE/install.sh" "$STAGE/uninstall.sh"

(cd "$(dirname "$STAGE")" && /usr/bin/zip -qry -X "$ZIP" "$NAME")
(cd "$ROOT/dist" && /usr/bin/shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "Packaged $ZIP"
