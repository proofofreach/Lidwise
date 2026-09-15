#!/bin/bash
# Shared install/remove operations. Command overrides are for isolated tests.
CLA_INSTALL_HOME=${CLA_INSTALL_HOME:-$HOME}
CLA_LAUNCHCTL=${CLA_LAUNCHCTL:-/bin/launchctl}
CLA_SUDO=${CLA_SUDO:-/usr/bin/sudo}
CLA_DITTO=${CLA_DITTO:-/usr/bin/ditto}
CLA_PMSET=${CLA_PMSET:-/usr/bin/pmset}
CLA_DAEMON_DIR=${CLA_DAEMON_DIR:-/Library/LaunchDaemons}
CLA_SUDOERS_DIR=${CLA_SUDOERS_DIR:-/etc/sudoers.d}
CLA_UID=$(id -u)
CLA_ACCOUNT=$(id -un)
case "$CLA_ACCOUNT" in *[!A-Za-z0-9._-]*) echo 'Unsupported account name' >&2; exit 1 ;; esac
APP_NAME='Closed-Lid Awake.app'
DEST_APP="$CLA_INSTALL_HOME/Applications/$APP_NAME"
WRAPPER="$CLA_INSTALL_HOME/.local/bin/vibecaf"
LOGIN_LABEL=app.closedlidawake.ClosedLidAwake
LOGIN_PLIST="$CLA_INSTALL_HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"
LEGACY_LABEL=app.closedlidawake.guardian
LEGACY_PLIST="$CLA_INSTALL_HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
DAEMON_LABEL="app.closedlidawake.guardian.$CLA_UID"
DAEMON_PLIST="$CLA_DAEMON_DIR/$DAEMON_LABEL.plist"
RULE="$CLA_SUDOERS_DIR/closed-lid-awake-$CLA_ACCOUNT"

installed_helper() {
  if [ -x "$DEST_APP/Contents/Resources/vibecaf" ]; then printf '%s\n' "$DEST_APP/Contents/Resources/vibecaf"
  elif [ -x "$WRAPPER" ]; then printf '%s\n' "$WRAPPER"
  else return 1; fi
}
read_phase() {
  local helper=${1:-} output phase
  if [ -n "$helper" ]; then
    if output=$("$helper" status --json 2>/dev/null); then
      phase=$(printf '%s' "$output" | /usr/bin/plutil -extract phase raw -o - - 2>/dev/null) || phase=
      case "$phase" in off|owned-on|external-on|unknown) printf '%s\n' "$phase"; return ;; esac
    fi
    # Upgrade compatibility with the old, unstructured CLI. Unknown fails closed.
    output=$("$helper" status 2>/dev/null) || { echo unknown; return; }
    case "$output" in 'AWAKE MODE: OFF'*) echo off ;; *) echo unknown ;; esac
  else
    output=$("$CLA_PMSET" -g 2>/dev/null) || { echo unknown; return; }
    phase=$(printf '%s\n' "$output" | awk '$1 == "SleepDisabled" {print $2}')
    case "$phase" in 0) echo off ;; *) echo unknown ;; esac
  fi
}
job_loaded() { "$CLA_LAUNCHCTL" print "$1" >/dev/null 2>&1; }
# Exact executable and user identity; never pkill a substring or trust stored PIDs.
app_pids() {
  /bin/ps -axo pid=,uid=,comm= | /usr/bin/awk -v uid="$CLA_UID" -v exe="$DEST_APP/Contents/MacOS/ClosedLidAwake" '
    $2 == uid { pid=$1; $1=""; $2=""; sub(/^ +/, ""); if ($0 == exe) print pid }'
}
stop_app() {
  local pid attempt
  for pid in $(app_pids); do
    case " $(app_pids | tr '\n' ' ') " in *" $pid "*) kill -TERM "$pid" ;; esac
  done
  for attempt in 1 2 3 4 5; do [ -z "$(app_pids)" ] && return 0; sleep 1; done
  echo 'The old app has not exited. Installation was stopped.' >&2; return 1
}

LEGACY_RULE="$CLA_SUDOERS_DIR/vibecaf-ipconfig"
legacy_rule_is_ours() {
  [ -f "$LEGACY_RULE" ] || return 1
  # The old grant had a global filename. Never delete another account's grant.
  local contents
  contents=$("$CLA_SUDO" /bin/cat "$LEGACY_RULE") || return 2
  printf '%s\n' "$contents" | /usr/bin/awk -v account="$CLA_ACCOUNT" '
    /^[[:space:]]*(#|$)/ { next }
    { seen=1; if ($1 != account || $0 !~ /ipconfig/) bad=1 }
    END { exit !(seen && !bad) }'
}
retire_legacy_rule() {
  local status=0
  legacy_rule_is_ours || status=$?
  case "$status" in
    0) "$CLA_SUDO" /bin/rm -f "$LEGACY_RULE" ;;
    1) [ ! -e "$LEGACY_RULE" ] || echo 'The legacy ipconfig rule belongs to another account or was customized; it was retained.' >&2 ;;
    *) echo 'Could not inspect the legacy permission rule; cleanup stopped.' >&2; return 1 ;;
  esac
}
