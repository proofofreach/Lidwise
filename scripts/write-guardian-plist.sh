#!/bin/bash
set -euo pipefail
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'usage: write-guardian-plist.sh <plist-path> <lidwise-path> [--system]' >&2; exit 2; }
PLIST=$1
VIBECAF=$2
MODE=${3:-}
INSTALL_HOME=${CLA_INSTALL_HOME:-$HOME}
LABEL=app.closedlidawake.guardian
if [ "$MODE" = --system ]; then LABEL="$LABEL.$(id -u)"; elif [ -n "$MODE" ]; then exit 2; fi
mkdir -p "$(dirname "$PLIST")"
rm -f "$PLIST"
/usr/bin/plutil -create xml1 "$PLIST"
/usr/bin/plutil -insert Label -string "$LABEL" "$PLIST"
/usr/bin/plutil -insert ProgramArguments -array "$PLIST"
/usr/bin/plutil -insert ProgramArguments.0 -string "$VIBECAF" "$PLIST"
/usr/bin/plutil -insert ProgramArguments.1 -string __guardian "$PLIST"
/usr/bin/plutil -insert EnvironmentVariables -dictionary "$PLIST"
/usr/bin/plutil -insert EnvironmentVariables.VIBECAF_NONINTERACTIVE -string 1 "$PLIST"
/usr/bin/plutil -insert EnvironmentVariables.HOME -string "$INSTALL_HOME" "$PLIST"
if [ "$MODE" = --system ]; then
  # A system job survives logout, but the user-writable helper MUST run as the user.
  /usr/bin/plutil -insert UserName -string "$(id -un)" "$PLIST"
fi
/usr/bin/plutil -insert RunAtLoad -bool true "$PLIST"
/usr/bin/plutil -insert KeepAlive -bool true "$PLIST"
/usr/bin/plutil -insert ProcessType -string Background "$PLIST"
/usr/bin/plutil -insert ThrottleInterval -integer 10 "$PLIST"
# The helper maintains its own bounded private logs; launchd output goes to null.
/usr/bin/plutil -insert StandardOutPath -string /dev/null "$PLIST"
/usr/bin/plutil -insert StandardErrorPath -string /dev/null "$PLIST"
/usr/bin/plutil -lint "$PLIST" >/dev/null
