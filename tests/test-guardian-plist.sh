#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-guardian-plist.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

PLIST="$TEST_ROOT/app.closedlidawake.guardian.plist"
VIBECAF="/tmp/Lidwise.app/Contents/Resources/lidwise"
"$ROOT/scripts/write-guardian-plist.sh" "$PLIST" "$VIBECAF"

[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST")" = "app.closedlidawake.guardian" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST")" = "$VIBECAF" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:1' "$PLIST")" = "__guardian" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:VIBECAF_NONINTERACTIVE' "$PLIST")" = "1" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$PLIST")" = "true" ]

echo "guardian plist: ok"
SYSTEM_PLIST="$TEST_ROOT/system.plist"
CLA_INSTALL_HOME="$TEST_ROOT/home with spaces" "$ROOT/scripts/write-guardian-plist.sh" "$SYSTEM_PLIST" "$VIBECAF" --system
[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$SYSTEM_PLIST")" = "app.closedlidawake.guardian.$(id -u)" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :UserName' "$SYSTEM_PLIST")" = "$(id -un)" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HOME' "$SYSTEM_PLIST")" = "$TEST_ROOT/home with spaces" ]
echo 'system guardian runs as the user: ok'
