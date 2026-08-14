#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}
BUILD_DIR="$ROOT/.build"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/Closed-Lid Awake.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$BUILD_DIR/appicon.iconset"
ARCHS=${ARCHS:-"arm64 x86_64"}

rm -rf "$BUILD_DIR" "$APP"
mkdir -p "$BUILD_DIR" "$MACOS" "$RESOURCES" "$ICONSET"

objects=()
for arch in $ARCHS; do
  output="$BUILD_DIR/ClosedLidAwake-$arch"
  xcrun swiftc \
    -O \
    -target "$arch-apple-macosx13.0" \
    -framework AppKit \
    -framework Carbon \
    "$ROOT/src/ClosedLidAwake.swift" \
    -o "$output"
  objects+=("$output")
done

if [ "${#objects[@]}" -eq 1 ]; then
  cp "${objects[0]}" "$MACOS/ClosedLidAwake"
else
  xcrun lipo -create "${objects[@]}" -output "$MACOS/ClosedLidAwake"
fi

install -m 0755 "$ROOT/bin/vibecaf" "$RESOURCES/vibecaf"

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

if [ -n "${SIGNING_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP"
else
  /usr/bin/codesign --force --sign - "$APP"
fi

/usr/bin/codesign --verify --deep --strict "$APP"
echo "Built $APP"
