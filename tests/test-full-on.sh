#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-session-features.XXXXXX")
export TEST_ROOT
cleanup() {
  [ ! -s "$TEST_ROOT/pids" ] || while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$TEST_ROOT/pids"
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NETLOG="$TEST_ROOT/state/logs/network.log"
export VIBECAF_PMSET="$TEST_ROOT/bin/pmset"
export VIBECAF_SUDO="$TEST_ROOT/bin/sudo"
export VIBECAF_OSASCRIPT="$TEST_ROOT/bin/osascript"
export VIBECAF_LAUNCHCTL="$TEST_ROOT/bin/launchctl"
export VIBECAF_CAFFEINATE="$TEST_ROOT/bin/caffeinate"
export VIBECAF_THERMAL_STATE_CMD="$TEST_ROOT/bin/thermal"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications"
export VIBECAF_NO_NETWATCH=1 VIBECAF_NO_OBSERVATION=1 VIBECAF_GUARD_EVERY=3600
export MOCK_PMSET_STATE="$TEST_ROOT/pmset-state" MOCK_PMSET_LOG="$TEST_ROOT/pmset.log"
export MOCK_THERMAL_STATE="$TEST_ROOT/thermal-state"
mkdir -p "$TEST_ROOT/bin" "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR"
: > "$TEST_ROOT/pids"

cat > "$VIBECAF_PMSET" <<'MOCK'
#!/bin/bash
set -u
case "$*" in
  "-g") printf 'System-wide power settings:\n SleepDisabled %s\n' "$(cat "$MOCK_PMSET_STATE")" ;;
  "-g batt") printf "Now drawing from '%s'\n -InternalBattery-0 %s%%; charged\n" "${MOCK_POWER_SOURCE:-AC Power}" "${MOCK_BATTERY_PCT:-100}" ;;
  "-a disablesleep "*)
    value=$3
    [ "$value" = 0 ] && [ "${MOCK_PMSET_SET0_FAIL:-0}" = 1 ] && exit 1
    printf '%s\n' "$value" >> "$MOCK_PMSET_LOG"
    printf '%s\n' "$value" > "$MOCK_PMSET_STATE" ;;
  *) exit 2 ;;
esac
MOCK
cat > "$VIBECAF_SUDO" <<'MOCK'
#!/bin/bash
set -u
list=0
while [ "$#" -gt 0 ]; do
  case "$1" in -n|-k) shift ;; -l|-ll) list=1; shift ;; --) shift; break ;; *) break ;; esac
done
if [ "$list" = 1 ]; then printf 'Options: !authenticate\n'; exit 0; fi
exec "$@"
MOCK
cat > "$VIBECAF_OSASCRIPT" <<'MOCK'
#!/bin/bash
exit 1
MOCK
cat > "$VIBECAF_LAUNCHCTL" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat > "$VIBECAF_CAFFEINATE" <<'MOCK'
#!/bin/bash
trap 'exit 0' TERM INT
while :; do sleep 1; done
MOCK
cat > "$VIBECAF_THERMAL_STATE_CMD" <<'MOCK'
#!/bin/bash
cat "$MOCK_THERMAL_STATE"
MOCK
chmod 0755 "$TEST_ROOT/bin/"*

VIBECAF="$ROOT/bin/lidwise"
printf '0\n' > "$MOCK_PMSET_STATE"
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
: > "$MOCK_PMSET_LOG"; : > "$VIBECAF_NOTIFY_LOG"

# Full On must persist without expiry, reject extension, and retain safety/recovery.
$VIBECAF config set duration 0 >/dev/null
$VIBECAF on >/dev/null
session="$VIBECAF_STATE_DIR/session"
[ "$(cat "$session/duration_seconds")" = 0 ]
[ "$(cat "$session/deadline")" = 0 ]
# Move the start past the former six-hour cap; Full On must still be valid.
printf '%s\n' "$(($(date +%s) - 86400))" > "$session/started_at"
$VIBECAF __guard_once
$VIBECAF __guardian_once
status=$($VIBECAF status --json)
printf '%s' "$status" | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["phase"] == "owned-on"; assert s["duration_seconds"] == 0; assert s["deadline"] is None; assert s["remaining_seconds"] is None; assert s["can_extend"] is False'
! $VIBECAF extend --by 1800 >/dev/null 2>&1
[ ! -s "$VIBECAF_NOTIFY_LOG" ]
$VIBECAF off >/dev/null
$VIBECAF history --json | python3 -c 'import json,sys; s=json.load(sys.stdin)["sessions"][0]; assert s["deadline"] == 0; assert s["restoration"] == "verified"'
$VIBECAF on --for 0 >/dev/null
env MOCK_BATTERY_PCT=10 $VIBECAF __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
$VIBECAF on --for 0 >/dev/null
printf 'critical\n' > "$MOCK_THERMAL_STATE"
$VIBECAF __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
$VIBECAF on --for 0 >/dev/null
printf '%s\n' "$(($(date +%s) - 3600))" > "$session/heartbeat"
$VIBECAF __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
# A timed policy with a zero deadline remains malformed and restores sleep.
$VIBECAF on --for 600 >/dev/null
printf '0\n' > "$session/deadline"
$VIBECAF __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
! $VIBECAF on --for 21601 >/dev/null 2>&1
! $VIBECAF extend --by 0 >/dev/null 2>&1
printf 'Full On end-to-end checks: PASS\n'
