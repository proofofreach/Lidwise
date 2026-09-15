#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
NAME="Closed-Lid-Awake-$VERSION-macos-universal"
DIST_DIR=${DIST_DIR:-"$ROOT/dist"}
mkdir -p "$ROOT/.build" "$DIST_DIR"
WORK=$(mktemp -d "$ROOT/.build/package.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/$NAME"
ZIP="$DIST_DIR/$NAME.zip"
if [ "${SKIP_BUILD:-0}" != 1 ]; then "$ROOT/scripts/build.sh"; fi
APP="$DIST_DIR/Closed-Lid Awake.app"
[ -d "$APP" ] || { echo 'Missing built app' >&2; exit 1; }
"$ROOT/scripts/source-manifest.sh" > "$WORK/current.sha256"
cmp "$WORK/current.sha256" "$APP/Contents/Resources/source-manifest.sha256" || { echo 'Source changed after build; rebuild before packaging.' >&2; exit 1; }
mkdir -p "$STAGE/scripts" "$STAGE/docs" "$STAGE/assets"
/usr/bin/ditto "$APP" "$STAGE/Closed-Lid Awake.app"
cp "$ROOT/scripts/"{install,uninstall}.sh "$STAGE/"
cp "$ROOT/scripts/"{lifecycle-common,write-guardian-plist}.sh "$STAGE/scripts/"
cp "$ROOT/"{VERSION,README.md,SECURITY.md,RELEASE_CHECKLIST.md,CHANGELOG.md,LICENSE} "$STAGE/"
for file in CLI.md NETWORK.md TROUBLESHOOTING.md COMPARISON.md; do [ ! -f "$ROOT/docs/$file" ] || cp "$ROOT/docs/$file" "$STAGE/docs/"; done
cp "$ROOT/assets/app-icon.png" "$STAGE/assets/"
(cd "$WORK" && /usr/bin/zip -qry -X "$WORK/$NAME.zip" "$NAME")
(cd "$WORK" && /usr/bin/shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
# A rejected build must never replace the last verified candidate.
"$ROOT/scripts/verify-release.sh" "${RELEASE_MODE:-development}" "$WORK/$NAME.zip"
mv "$WORK/$NAME.zip.sha256" "$ZIP.sha256"
mv "$WORK/$NAME.zip" "$ZIP"
echo "Packaged $ZIP"
