#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Closed-Lid Awake.app"
WRAPPER="$HOME/.local/bin/vibecaf"
LABEL="app.closedlidawake.ClosedLidAwake"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUARDIAN_LABEL="app.closedlidawake.guardian"
GUARDIAN_PLIST="$HOME/Library/LaunchAgents/$GUARDIAN_LABEL.plist"
account=$(id -un)

if [ -x "$WRAPPER" ]; then
  "$WRAPPER" off || {
    echo "Could not restore normal sleep. Resolve that before uninstalling." >&2
    exit 1
  }
fi

/bin/launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
/bin/launchctl bootout "gui/$(id -u)/$GUARDIAN_LABEL" 2>/dev/null || true
rm -f "$PLIST" "$GUARDIAN_PLIST" "$WRAPPER"
rm -rf "$APP"

# The second file is a retired grant: the DHCP renew briefly ran through a
# root-only `ipconfig set`, first via `vibecaf install-sudoers`, then via an
# install.sh rule, before moving to unprivileged service-layer networksetup
# (see dhcp_renew in bin/vibecaf). Remove it wherever it still exists.
for rule in "/etc/sudoers.d/closed-lid-awake-$account" /etc/sudoers.d/vibecaf-ipconfig; do
  if [ -e "$rule" ]; then
    sudo rm -f "$rule"
  fi
done

echo "Removed Closed-Lid Awake. Normal sleep is enabled."
