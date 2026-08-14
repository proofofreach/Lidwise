#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/Closed-Lid Awake.app"

for script in "$ROOT"/bin/vibecaf*; do /bin/bash -n "$script"; done
for script in "$ROOT"/scripts/*.sh; do /bin/bash -n "$script"; done
for test_script in "$ROOT"/tests/*.sh; do /bin/bash -n "$test_script"; done
for test_script in "$ROOT"/tests/*.sh; do "$test_script"; done
xcrun swiftc -typecheck -framework AppKit -framework Carbon \
  "$ROOT/src/ClosedLidAwake.swift"
xcrun swiftc -typecheck "$ROOT/src/ThermalState.swift"
xcrun swiftc -typecheck "$ROOT/src/makeicon.swift"

"$ROOT/scripts/build.sh"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"

arches=$(/usr/bin/lipo -archs "$APP/Contents/MacOS/ClosedLidAwake")
thermal_arches=$(/usr/bin/lipo -archs "$APP/Contents/Resources/vibecaf-thermal")
for required in arm64 x86_64; do
  case " $arches " in
    *" $required "*) ;;
    *) echo "Missing architecture: $required" >&2; exit 1 ;;
  esac
  case " $thermal_arches " in
    *" $required "*) ;;
    *) echo "Thermal helper missing architecture: $required" >&2; exit 1 ;;
  esac
done

if rg -n '/Users/[^/]+|com\.k\.|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|api[_-]?key|access[_-]?token' \
  "$ROOT" --glob '!dist/**' --glob '!.build/**' --glob '!scripts/check.sh'; then
  echo "Potential private or machine-specific content found." >&2
  exit 1
fi

echo "Checks passed for: $arches"
