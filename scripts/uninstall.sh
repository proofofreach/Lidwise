#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Closed-Lid Awake.app"
WRAPPER="$HOME/.local/bin/vibecaf"
LABEL="app.closedlidawake.ClosedLidAwake"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
account=$(id -un)

if [ -x "$WRAPPER" ]; then
  "$WRAPPER" off || {
    echo "Could not restore normal sleep. Resolve that before uninstalling." >&2
    exit 1
  }
fi

/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$WRAPPER"
rm -rf "$APP"

rule="/etc/sudoers.d/closed-lid-awake-$account"
if [ -e "$rule" ]; then
  sudo rm -f "$rule"
fi

echo "Removed Closed-Lid Awake. Normal sleep is enabled."
