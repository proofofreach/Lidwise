#!/bin/bash
# Verify the files users actually extract. Development mode never certifies distribution.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-production}
ZIP=${2:-}
case "$MODE" in development|community|production) ;; *) echo 'usage: verify-release.sh development|community|production archive.zip' >&2; exit 2 ;; esac
[ -f "$ZIP" ] && [ -f "$ZIP.sha256" ] || { echo 'Archive and checksum are required' >&2; exit 1; }
ZIP=$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")
(cd "$(dirname "$ZIP")" && /usr/bin/shasum -a 256 -c "$(basename "$ZIP").sha256")
WORK=$(mktemp -d "${TMPDIR:-/tmp}/closedlid-verify.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Reject path traversal before extracting even locally produced archives.
/usr/bin/unzip -Z1 "$ZIP" | awk '/(^\/|(^|\/)\.\.(\/|$))/ { bad=1 } END { exit bad }'
/usr/bin/zipinfo -l "$ZIP" | awk '$1 ~ /^l/ { bad=1 } END { exit bad }'
/usr/bin/ditto -x -k "$ZIP" "$WORK"
shopt -s dotglob nullglob
packages=("$WORK"/*)
shopt -u dotglob nullglob
[ "${#packages[@]}" -eq 1 ] && [ -d "${packages[0]}" ] || { echo 'Expected one package root' >&2; exit 1; }
PACKAGE=${packages[0]}
APP="$PACKAGE/Closed-Lid Awake.app"
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" = "$VERSION" ] || { echo 'Version mismatch' >&2; exit 1; }
"$ROOT/scripts/source-manifest.sh" > "$WORK/current.sha256"
cmp "$WORK/current.sha256" "$APP/Contents/Resources/source-manifest.sha256" || { echo 'Artifact differs from current release inputs; rebuild.' >&2; exit 1; }
for file in install.sh uninstall.sh scripts/lifecycle-common.sh scripts/write-guardian-plist.sh; do
  [ -x "$PACKAGE/$file" ] || { echo "Missing executable $file" >&2; exit 1; }
  /bin/bash -n "$PACKAGE/$file"
  source="$ROOT/$file"
  case "$file" in install.sh|uninstall.sh) source="$ROOT/scripts/$file" ;; esac
  cmp "$source" "$PACKAGE/$file"
done
for file in vibecaf vibecaf-agent-scan; do cmp "$ROOT/bin/$file" "$APP/Contents/Resources/$file"; done
for source in "$ROOT"/lib/vibecaf/*.sh; do cmp "$source" "$APP/Contents/Resources/lib/vibecaf/$(basename "$source")"; done
/usr/bin/codesign --verify --deep --strict "$APP"
# No executable or other undeclared payload may hide beside the app.
while IFS= read -r -d '' file; do
  case "$file" in
    "$APP"/*|"$PACKAGE/install.sh"|"$PACKAGE/uninstall.sh"|"$PACKAGE/scripts/lifecycle-common.sh"|"$PACKAGE/scripts/write-guardian-plist.sh"|"$PACKAGE/VERSION"|"$PACKAGE/README.md"|"$PACKAGE/SECURITY.md"|"$PACKAGE/RELEASE_CHECKLIST.md"|"$PACKAGE/CHANGELOG.md"|"$PACKAGE/LICENSE"|"$PACKAGE/assets/app-icon.png"|"$PACKAGE/docs/CLI.md"|"$PACKAGE/docs/NETWORK.md"|"$PACKAGE/docs/TROUBLESHOOTING.md"|"$PACKAGE/docs/COMPARISON.md") ;;
    *) echo "Unexpected archive file: $file" >&2; exit 1 ;;
  esac
done < <(/usr/bin/find "$PACKAGE" -type f -print0)
for file in VERSION README.md SECURITY.md RELEASE_CHECKLIST.md CHANGELOG.md LICENSE assets/app-icon.png docs/CLI.md docs/NETWORK.md docs/TROUBLESHOOTING.md docs/COMPARISON.md; do
  cmp "$ROOT/$file" "$PACKAGE/$file"
done
team=
count=0
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | /usr/bin/grep -q 'Mach-O'; then
    count=$((count + 1))
    arches=$(/usr/bin/lipo -archs "$file")
    for arch in arm64 x86_64; do
      case " $arches " in *" $arch "*) ;; *) echo "Missing $arch in $file" >&2; exit 1 ;; esac
    done
    /usr/bin/codesign --verify --strict "$file"
    details=$(/usr/bin/codesign -dvv "$file" 2>&1)
    if [ "$MODE" = production ]; then
      printf '%s\n' "$details" | /usr/bin/grep -q '^Authority=Developer ID Application:'
      printf '%s\n' "$details" | /usr/bin/grep -q 'flags=.*runtime'
      printf '%s\n' "$details" | /usr/bin/grep -q '^Timestamp='
      file_team=$(printf '%s\n' "$details" | /usr/bin/sed -n 's/^TeamIdentifier=//p')
      [ -n "$file_team" ] && [ "$file_team" != not\ set ]
      if [ -z "$team" ]; then team=$file_team; else [ "$team" = "$file_team" ]; fi
    fi
  fi
done < <(/usr/bin/find "$APP" -type f -print0)
[ "$count" -eq 3 ] || { echo 'Native app/helper missing' >&2; exit 1; }
[ -x "$APP/Contents/Helpers/vibecaf-thermal" ]
[ -x "$APP/Contents/Helpers/vibecaf-agent-scan-core" ]
[ ! -e "$APP/Contents/Resources/vibecaf-thermal" ]
if [ "$MODE" = production ]; then
  xcrun stapler validate "$APP"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP"
  echo "Production signature, notarization and extracted-content checks passed ($count native executables). Hardware gates are separate."
elif [ "$MODE" = community ]; then
  echo "Community archive verified ($count universal native executables). Not notarized; Gatekeeper approval is required. Hardware gates are separate."
else
  echo "Development archive verified ($count native executables). This does not pass the distribution gate."
fi
