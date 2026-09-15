#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
if [ -f "$SCRIPT_DIR/scripts/lifecycle-common.sh" ]; then ROOT="$SCRIPT_DIR"; fi
source "$ROOT/scripts/lifecycle-common.sh"
[ "$#" -eq 0 ] || { echo 'usage: uninstall.sh' >&2; exit 2; }
if [ "$PREVIOUS_APP" = "$OLD_APP" ]; then
  echo 'Use the Closed-Lid Awake uninstaller for the existing app, or upgrade to Lidwise first. Nothing was removed.' >&2
  exit 1
fi
helper=$(installed_helper || true)
# Current helpers restore an owned session while acquiring the same lock used by
# on/off. Legacy installations can use this release's helper for the lock protocol.
maintenance_helper=$helper
if [ ! -f "$DEST_APP/Contents/Resources/lib/lidwise/session.sh" ]; then
  if [ -x "$ROOT/bin/lidwise" ]; then maintenance_helper="$ROOT/bin/lidwise"
  elif [ -x "$ROOT/$APP_NAME/Contents/Resources/lidwise" ]; then maintenance_helper="$ROOT/$APP_NAME/Contents/Resources/lidwise"
  fi
fi
if [ "${CLA_MAINTENANCE_ACTIVE:-0}" != 1 ] && [ -n "$maintenance_helper" ]; then
  exec "$maintenance_helper" __maintenance --remove -- \
    /usr/bin/env CLA_MAINTENANCE_ACTIVE=1 /bin/bash "$0" "$@"
fi
phase=$(read_phase "$helper")
case "$phase" in
  owned-on)
    [ "${CLA_MAINTENANCE_ACTIVE:-0}" != 1 ] || { echo 'Owned session remains active under maintenance; removal stopped.' >&2; exit 1; }
    "$helper" off || { echo 'Could not restore sleep. Recovery files and permission are retained.' >&2; exit 1; }
    [ "$(read_phase "$helper")" = off ] || { echo 'Sleep restoration could not be verified. Nothing was removed.' >&2; exit 1; } ;;
  off|external-on) ;;
  *) echo 'Power state is unknown. Repair the app or restore sleep before uninstalling; safeguards were retained.' >&2; exit 1 ;;
esac
# Authenticate before changing hook settings or stopping recovery.
echo 'Sleep state checked. Administrator approval is needed to remove recovery setup.'
"$CLA_SUDO" -v
# Releases with session history also provide the lifecycle-hook adapter. Remove
# its owned commands before deleting the executable those commands reference.
# Earlier releases never installed these hooks and have no history module.
if [ -f "$DEST_APP/Contents/Resources/lib/lidwise/history.sh" ]; then
  "$helper" hooks remove all || {
    echo 'Could not remove agent hooks. The app and recovery setup were retained. Repair the hook configuration and retry.' >&2
    exit 1
  }
fi
job_loaded "gui/$CLA_UID/$LOGIN_LABEL" && "$CLA_LAUNCHCTL" bootout "gui/$CLA_UID/$LOGIN_LABEL"
stop_app
job_loaded "system/$DAEMON_LABEL" && "$CLA_SUDO" "$CLA_LAUNCHCTL" bootout "system/$DAEMON_LABEL"
job_loaded "gui/$CLA_UID/$LEGACY_LABEL" && "$CLA_LAUNCHCTL" bootout "gui/$CLA_UID/$LEGACY_LABEL"
# Keep the app and its recovery permission if removal of its daemon fails.
retire_legacy_rule
"$CLA_SUDO" /bin/rm -f "$DAEMON_PLIST"
"$CLA_SUDO" /bin/rm -f "$RULE"
# Only remove the compatibility wrapper when it is identical to this install's wrapper.
if [ -f "$WRAPPER" ] && [ -f "$OLD_WRAPPER" ] && cmp -s "$WRAPPER" "$OLD_WRAPPER"; then rm -f "$OLD_WRAPPER"; fi
rm -f "$LOGIN_PLIST" "$LEGACY_PLIST" "$WRAPPER"
rm -rf "$DEST_APP"
if [ "$phase" = external-on ]; then
  echo 'Removed Lidwise. Another tool’s sleep hold remains active.'
else
  echo 'Removed Lidwise. Normal sleep was verified before removal.'
fi
