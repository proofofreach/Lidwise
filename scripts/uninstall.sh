#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Lidwise.app"
WRAPPER="$HOME/.local/bin/lidwise"
LABEL="com.proofofreach.Lidwise"
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

rule="/etc/sudoers.d/lidwise-$account"
if [ -e "$rule" ]; then
  sudo rm -f "$rule"
fi

# Pre-rename install (v1.0.0 and earlier): Closed-Lid Awake.
LEGACY_LABEL="app.closedlidawake.ClosedLidAwake"
LEGACY_WRAPPER="$HOME/.local/bin/vibecaf"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_RULE="/etc/sudoers.d/closed-lid-awake-$account"
if [ -x "$LEGACY_WRAPPER" ]; then
  "$LEGACY_WRAPPER" off || {
    echo "Could not restore normal sleep. Resolve that before uninstalling." >&2
    exit 1
  }
fi
/bin/launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" 2>/dev/null || true
rm -f "$LEGACY_PLIST" "$LEGACY_WRAPPER"
rm -rf "$HOME/Applications/Closed-Lid Awake.app"
if [ -e "$LEGACY_RULE" ]; then
  sudo rm -f "$LEGACY_RULE"
fi

echo "Removed Lidwise. Normal sleep is enabled."
