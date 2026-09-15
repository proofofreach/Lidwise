#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
if [ -f "$SCRIPT_DIR/scripts/lifecycle-common.sh" ]; then ROOT="$SCRIPT_DIR"; fi
source "$ROOT/scripts/lifecycle-common.sh"
with_sudoers=1
case "${1:-}" in --without-sudoers) with_sudoers=0 ;; '') ;; *) echo 'usage: install.sh [--without-sudoers]' >&2; exit 2 ;; esac
[ "$#" -le 1 ] || exit 2
SOURCE_APP=${CLA_SOURCE_APP:-"$ROOT/dist/$APP_NAME"}
[ -d "$SOURCE_APP" ] || SOURCE_APP="$ROOT/$APP_NAME"
[ -d "$SOURCE_APP" ] || { echo 'Build or extract the release before installing.' >&2; exit 1; }
# The candidate helper holds the shared mutation lock throughout staging/upgrade.
# The script child only reads power state; it never invokes a mutating CLI command.
if [ "${CLA_MAINTENANCE_ACTIVE:-0}" != 1 ]; then
  exec "$SOURCE_APP/Contents/Resources/vibecaf" __maintenance -- \
    /usr/bin/env CLA_MAINTENANCE_ACTIVE=1 /bin/bash "$0" "$@"
fi
helper=$(installed_helper || true)
phase=$(read_phase "$helper")
[ "$phase" = off ] || { echo "Installation requires verified normal sleep (current state: $phase). Turn awake mode off first." >&2; exit 1; }
mkdir -p "$CLA_INSTALL_HOME/Applications" "$CLA_INSTALL_HOME/.local/bin" "$CLA_INSTALL_HOME/Library/LaunchAgents"
WORK=$(mktemp -d "$CLA_INSTALL_HOME/Applications/.closedlid-install.XXXXXX")
chmod 0700 "$WORK"
mutated=0; committed=0; app_saved=0; new_app=0; rule_changed=0; daemon_changed=0; legacy_rule_changed=0
login_loaded=0; legacy_loaded=0; daemon_loaded=0; app_running=0
job_loaded "gui/$CLA_UID/$LOGIN_LABEL" && login_loaded=1
job_loaded "gui/$CLA_UID/$LEGACY_LABEL" && legacy_loaded=1
job_loaded "system/$DAEMON_LABEL" && daemon_loaded=1
[ -n "$(app_pids)" ] && app_running=1
cleanup() {
  result=$?
  trap - EXIT INT TERM
  rollback_failed=0
  if [ "$committed" -eq 0 ] && [ "$mutated" -eq 1 ]; then
    echo 'Installation failed; restoring the previous installation.' >&2
    if job_loaded "system/$DAEMON_LABEL"; then
      "$CLA_SUDO" "$CLA_LAUNCHCTL" bootout "system/$DAEMON_LABEL" || rollback_failed=1
    fi
    if [ "$new_app" -eq 1 ]; then rm -rf "$DEST_APP" || rollback_failed=1; fi
    if [ "$app_saved" -eq 1 ]; then mv "$WORK/previous.app" "$DEST_APP" || rollback_failed=1; fi
    if [ -e "$WORK/wrapper" ]; then cp -p "$WORK/wrapper" "$WRAPPER" || rollback_failed=1
    else rm -f "$WRAPPER" || rollback_failed=1; fi
    if [ "$rule_changed" -eq 1 ]; then
      if [ -e "$WORK/rule" ]; then "$CLA_SUDO" /usr/bin/install -o root -g wheel -m 0440 "$WORK/rule" "$RULE" || rollback_failed=1
      else "$CLA_SUDO" /bin/rm -f "$RULE" || rollback_failed=1; fi
    fi
    if [ "$legacy_rule_changed" -eq 1 ]; then
      "$CLA_SUDO" /usr/bin/install -o root -g wheel -m 0440 "$WORK/legacy-rule" "$LEGACY_RULE" || rollback_failed=1
    fi
    if [ "$daemon_changed" -eq 1 ]; then
      if [ -e "$WORK/daemon.plist" ]; then "$CLA_SUDO" /usr/bin/install -o root -g wheel -m 0644 "$WORK/daemon.plist" "$DAEMON_PLIST" || rollback_failed=1
      else "$CLA_SUDO" /bin/rm -f "$DAEMON_PLIST" || rollback_failed=1; fi
    fi
    if [ "$daemon_loaded" -eq 1 ]; then "$CLA_SUDO" "$CLA_LAUNCHCTL" bootstrap system "$DAEMON_PLIST" || rollback_failed=1; fi
    if [ "$legacy_loaded" -eq 1 ]; then "$CLA_LAUNCHCTL" bootstrap "gui/$CLA_UID" "$LEGACY_PLIST" || rollback_failed=1; fi
    if [ "$login_loaded" -eq 1 ]; then "$CLA_LAUNCHCTL" bootstrap "gui/$CLA_UID" "$LOGIN_PLIST" || rollback_failed=1; fi
    if [ "$app_running" -eq 1 ] && [ "$login_loaded" -eq 0 ]; then /usr/bin/open "$DEST_APP" || rollback_failed=1; fi
  fi
  if [ "$rollback_failed" -eq 1 ]; then
    echo "Rollback was incomplete. Recovery backups are retained at: $WORK" >&2
    echo 'Keep normal sleep enabled and repair the installation before starting a session.' >&2
    exit 1
  fi
  rm -rf "$WORK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$CLA_DITTO" "$SOURCE_APP" "$WORK/new.app"
for file in Contents/MacOS/ClosedLidAwake Contents/Resources/vibecaf Contents/Resources/vibecaf-agent-scan Contents/Helpers/vibecaf-thermal Contents/Helpers/vibecaf-agent-scan-core; do
  [ -x "$WORK/new.app/$file" ] || { echo "Incomplete app: $file" >&2; exit 1; }
done
for module in session network observation; do
  [ -f "$WORK/new.app/Contents/Resources/lib/vibecaf/$module.sh" ] || { echo "Missing helper module: $module" >&2; exit 1; }
done
/usr/bin/codesign --verify --deep --strict "$WORK/new.app"
[ ! -e "$WRAPPER" ] || cp -p "$WRAPPER" "$WORK/wrapper"
# Authenticate and validate before stopping the app or removing any safeguards.
"$CLA_SUDO" -v
[ ! -e "$RULE" ] || "$CLA_SUDO" /bin/cat "$RULE" > "$WORK/rule"
[ ! -e "$LEGACY_RULE" ] || "$CLA_SUDO" /bin/cat "$LEGACY_RULE" > "$WORK/legacy-rule"
[ ! -e "$DAEMON_PLIST" ] || "$CLA_SUDO" /bin/cat "$DAEMON_PLIST" > "$WORK/daemon.plist"
if [ "$with_sudoers" -eq 1 ]; then
  printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$CLA_ACCOUNT" > "$WORK/new-rule"
  "$CLA_SUDO" /usr/sbin/visudo -cf "$WORK/new-rule"
fi
CLA_INSTALL_HOME="$CLA_INSTALL_HOME" "$ROOT/scripts/write-guardian-plist.sh" "$WORK/new-daemon.plist" "$DEST_APP/Contents/Resources/vibecaf" --system
# Recheck after staging/authentication, before any mutation.
[ "$(read_phase "$helper")" = off ] || { echo 'Power state changed during staging; retry after turning awake mode off.' >&2; exit 1; }
mutated=1
[ "$login_loaded" -eq 0 ] || "$CLA_LAUNCHCTL" bootout "gui/$CLA_UID/$LOGIN_LABEL"
stop_app
# Closing the old UI can race a legacy helper launched just before it exited.
# Recheck while its recovery services are still intact.
[ "$(read_phase "$helper")" = off ] || { echo 'Power state changed while the old app exited; safeguards are retained.' >&2; exit 1; }
[ "$legacy_loaded" -eq 0 ] || "$CLA_LAUNCHCTL" bootout "gui/$CLA_UID/$LEGACY_LABEL"
[ "$daemon_loaded" -eq 0 ] || "$CLA_SUDO" "$CLA_LAUNCHCTL" bootout "system/$DAEMON_LABEL"
if [ -e "$DEST_APP" ]; then mv "$DEST_APP" "$WORK/previous.app"; app_saved=1; fi
mv "$WORK/new.app" "$DEST_APP"; new_app=1
printf '#!/bin/bash\nexec %q "$@"\n' "$DEST_APP/Contents/Resources/vibecaf" > "$WORK/new-wrapper"
chmod 0755 "$WORK/new-wrapper"
mv "$WORK/new-wrapper" "$WRAPPER"
if [ "$with_sudoers" -eq 1 ]; then
  rule_changed=1
  "$CLA_SUDO" /usr/bin/install -o root -g wheel -m 0440 "$WORK/new-rule" "$RULE"
fi
daemon_changed=1
"$CLA_SUDO" /usr/bin/install -o root -g wheel -m 0644 "$WORK/new-daemon.plist" "$DAEMON_PLIST"
"$CLA_SUDO" "$CLA_LAUNCHCTL" bootstrap system "$DAEMON_PLIST"
job_loaded "system/$DAEMON_LABEL" || { echo 'Guardian did not start' >&2; exit 1; }
if legacy_rule_is_ours; then legacy_rule_changed=1; fi
retire_legacy_rule
# Preserve login preference. Do not bootstrap it now: its login-only awake action
# must not run during an upgrade. A running menu app is reopened once, manually.
if [ "$app_running" -eq 1 ]; then /usr/bin/open "$DEST_APP"; fi
committed=1
rm -f "$LEGACY_PLIST"
echo "Installed $DEST_APP"
[ "$with_sudoers" -eq 1 ] || echo 'No new sleep permission rule was installed. Activation requires durable recovery permission.'
echo 'Open the app and use Check setup before starting a session.'
