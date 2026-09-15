#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}
mkdir -p "$ROOT/.build"
BUILD_DIR=$(mktemp -d "$ROOT/.build/app.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
DIST_DIR=${DIST_DIR:-"$ROOT/dist"}
APP="$DIST_DIR/Closed-Lid Awake.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$BUILD_DIR/appicon.iconset"
ARCHS=${ARCHS:-"arm64 x86_64"}
"$ROOT/scripts/source-manifest.sh" > "$BUILD_DIR/inputs-before.sha256"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES/lib/vibecaf" "$CONTENTS/Helpers" "$ICONSET"
HELPERS_DIR="$CONTENTS/Helpers" "$ROOT/scripts/build-helpers.sh"

cp "$ROOT/src/ClosedLidAwake.swift" "$BUILD_DIR/main.swift"
ui_sources=("$BUILD_DIR/main.swift")
for source in "$ROOT"/src/*.swift; do
  case "$(basename "$source")" in ClosedLidAwake.swift|ThermalState.swift|AgentScan.swift|makeicon.swift) continue ;; esac
  ui_sources+=("$source")
done
objects=()

for arch in $ARCHS; do
  output="$BUILD_DIR/ClosedLidAwake-$arch"
  xcrun swiftc \
    -O \
    -target "$arch-apple-macosx13.0" \
    -framework AppKit \
    -framework Carbon \
    "${ui_sources[@]}" \
    -o "$output"
  objects+=("$output")


done

if [ "${#objects[@]}" -eq 1 ]; then
  cp "${objects[0]}" "$MACOS/ClosedLidAwake"
else
  xcrun lipo -create "${objects[@]}" -output "$MACOS/ClosedLidAwake"
fi


install -m 0755 "$ROOT/bin/vibecaf" "$RESOURCES/vibecaf"
install -m 0755 "$ROOT/bin/vibecaf-agent-scan" "$RESOURCES/vibecaf-agent-scan"
install -m 0644 "$ROOT"/lib/vibecaf/*.sh "$RESOURCES/lib/vibecaf/"

xcrun swiftc "$ROOT/src/makeicon.swift" -o "$BUILD_DIR/makeicon"
"$BUILD_DIR/makeicon" "$BUILD_DIR/appicon.png"

make_icon() {
  local pixels=$1 name=$2
  /usr/bin/sips -z "$pixels" "$pixels" "$BUILD_DIR/appicon.png" \
    --out "$ICONSET/$name" >/dev/null
}
make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
/usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCES/appicon.icns"

PLIST="$CONTENTS/Info.plist"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert CFBundleDisplayName -string "Closed-Lid Awake" "$PLIST"
/usr/bin/plutil -insert CFBundleExecutable -string "ClosedLidAwake" "$PLIST"
/usr/bin/plutil -insert CFBundleIconFile -string "appicon" "$PLIST"
/usr/bin/plutil -insert CFBundleIdentifier -string "app.closedlidawake.ClosedLidAwake" "$PLIST"
/usr/bin/plutil -insert CFBundleName -string "Closed-Lid Awake" "$PLIST"
/usr/bin/plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
/usr/bin/plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
/usr/bin/plutil -insert CFBundleVersion -string "${BUILD_NUMBER:-1}" "$PLIST"
/usr/bin/plutil -insert LSMinimumSystemVersion -string "13.0" "$PLIST"
/usr/bin/plutil -insert LSUIElement -bool true "$PLIST"
/usr/bin/plutil -insert NSHighResolutionCapable -bool true "$PLIST"

"$ROOT/scripts/source-manifest.sh" > "$RESOURCES/source-manifest.sha256"
cmp "$BUILD_DIR/inputs-before.sha256" "$RESOURCES/source-manifest.sha256" || { echo "Release inputs changed during the build; retry after edits finish." >&2; exit 1; }
/usr/bin/plutil -insert CLASourceRevision -string "$(git -C "$ROOT" rev-parse HEAD)" "$PLIST"

if [ -n "${SIGNING_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP"
fi

/usr/bin/codesign --verify --deep --strict "$APP"
echo "Built $APP"
