#!/bin/bash
set -euo pipefail

[ "$#" -eq 2 ] || { echo "usage: $0 <plist-path> <vibecaf-path>" >&2; exit 2; }

PLIST=$1
VIBECAF=$2
mkdir -p "$(dirname "$PLIST")"
rm -f "$PLIST"

/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert Label -string "app.closedlidawake.guardian" "$PLIST"
/usr/bin/plutil -insert ProgramArguments -array "$PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$VIBECAF" "$PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string "__guardian" "$PLIST"
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$PLIST"
/usr/bin/plutil -insert EnvironmentVariables.VIBECAF_NONINTERACTIVE -string "1" "$PLIST"
/usr/bin/plutil -insert RunAtLoad -bool true "$PLIST"
/usr/bin/plutil -insert KeepAlive -bool true "$PLIST"
/usr/bin/plutil -insert ProcessType -string "Background" "$PLIST"
/usr/bin/plutil -insert ThrottleInterval -integer 10 "$PLIST"
/usr/bin/plutil -insert StandardOutPath -string "$HOME/Library/Logs/closedlidawake-guardian.log" "$PLIST"
/usr/bin/plutil -insert StandardErrorPath -string "$HOME/Library/Logs/closedlidawake-guardian.log" "$PLIST"
/usr/bin/plutil -lint "$PLIST" >/dev/null
