#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-safety.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NETLOG="$TEST_ROOT/state/logs/network.log"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
export VIBECAF_PMSET="$TEST_ROOT/bin/pmset"
export VIBECAF_SUDO="$TEST_ROOT/bin/sudo"
export VIBECAF_THERMAL_STATE_CMD="$TEST_ROOT/bin/thermal-state"
export VIBECAF_LAUNCHCTL="$TEST_ROOT/bin/launchctl"
export MOCK_PMSET_STATE="$TEST_ROOT/pmset-state"
export MOCK_THERMAL_STATE="$TEST_ROOT/thermal-state"
mkdir -p "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR/session" "$TEST_ROOT/bin"
chmod 700 "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR" "$VIBECAF_STATE_DIR/session"

cat > "$VIBECAF_PMSET" <<'MOCK'
#!/bin/bash
set -e
case "$1 ${2:-}" in
  "-g batt") echo "Now drawing from '${MOCK_POWER_SOURCE:-AC Power}'"; echo " -InternalBattery-0 (id=1) ${MOCK_BATTERY_PCT:-100}%; charged" ;;
  "-g ") [ "${MOCK_PMSET_QUERY_FAIL:-0}" = "1" ] && exit 1; echo " SleepDisabled $(cat "$MOCK_PMSET_STATE")"; echo " standby 1" ;;
  "-a disablesleep") printf '%s\n' "$3" > "$MOCK_PMSET_STATE" ;;
  *) exit 2 ;;
esac
MOCK

cat > "$VIBECAF_SUDO" <<'MOCK'
#!/bin/bash
[ "${MOCK_SUDO_FAIL:-0}" = "1" ] && exit 1
[ "${1:-}" = "-n" ] && shift
exec "$@"
MOCK

cat > "$VIBECAF_THERMAL_STATE_CMD" <<'MOCK'
#!/bin/bash
cat "$MOCK_THERMAL_STATE"
MOCK
cat > "$VIBECAF_LAUNCHCTL" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod 0755 "$VIBECAF_PMSET" "$VIBECAF_SUDO" "$VIBECAF_THERMAL_STATE_CMD" "$VIBECAF_LAUNCHCTL"

VIBECAF="$ROOT/bin/lidwise"

printf '0\n' > "$MOCK_PMSET_STATE"
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
grep -q '^AWAKE MODE: OFF$' <("$VIBECAF" status)

begin_fake_session() {
  local now
  now=$(date +%s)
  printf '1\n' > "$MOCK_PMSET_STATE"
  printf 'test-session\n' > "$VIBECAF_STATE_DIR/session/id"
  printf 'active\n' > "$VIBECAF_STATE_DIR/session/state"
  printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/started_at"
  printf '%s\n' "$((now + 21600))" > "$VIBECAF_STATE_DIR/session/deadline"
  printf '21600\n' > "$VIBECAF_STATE_DIR/session/duration_seconds"
  printf '20\n' > "$VIBECAF_STATE_DIR/session/battery_floor"
  printf '1\n' > "$VIBECAF_STATE_DIR/session/recovery"
  printf '0\n' > "$VIBECAF_STATE_DIR/session/notifications"
  printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/heartbeat"
}

begin_fake_session
printf 'critical\n' > "$MOCK_THERMAL_STATE"
"$VIBECAF" __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode turned off\tthermal pressure: critical' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
printf 'serious\n' > "$MOCK_THERMAL_STATE"
VIBECAF_THERMAL_STRIKES=3 "$VIBECAF" __guard_once
VIBECAF_THERMAL_STRIKES=3 "$VIBECAF" __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]
VIBECAF_THERMAL_STRIKES=3 "$VIBECAF" __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode turned off\tthermal pressure: serious for 3 checks' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
MOCK_POWER_SOURCE="Battery Power" MOCK_BATTERY_PCT=10 VIBECAF_BATTERY_FLOOR=20 "$VIBECAF" __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode turned off\tbattery floor: 10% on battery' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
MOCK_SUDO_FAIL=1 MOCK_POWER_SOURCE="Battery Power" MOCK_BATTERY_PCT=10 \
  VIBECAF_NONINTERACTIVE=1 VIBECAF_BATTERY_FLOOR=20 "$VIBECAF" __guard_once || true
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]
grep -q $'Safety recovery failed\tbattery floor: 10% on battery; normal sleep is still blocked' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
printf '1\n' > "$VIBECAF_STATE_DIR/session/heartbeat"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode recovered\tguard heartbeat lost' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
MOCK_PMSET_QUERY_FAIL=1 "$VIBECAF" __guardian_once || true
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]
[ -e "$VIBECAF_STATE_DIR/session/id" ]

# Corrupt durable timestamps fail safe instead of crashing the guardian.
begin_fake_session
printf 'not-a-time\n' > "$VIBECAF_STATE_DIR/session/heartbeat"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]

# Numeric deadline corruption and invalid battery policy also trigger
# conservative automatic restoration.
begin_fake_session
now=$(date +%s)
printf '60\n' > "$VIBECAF_STATE_DIR/session/duration_seconds"
printf '%s\n' "$((now + 86400))" > "$VIBECAF_STATE_DIR/session/deadline"
"$VIBECAF" __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode turned off\towned session policy is invalid' "$VIBECAF_NOTIFY_LOG"

begin_fake_session
printf '0\n' > "$VIBECAF_STATE_DIR/session/battery_floor"
"$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]
grep -q $'Awake mode recovered\towned session policy is invalid' "$VIBECAF_NOTIFY_LOG"

# Never undo another tool's disablesleep setting when this app has no durable
# ownership record.
rm -rf "$VIBECAF_STATE_DIR/session"
mkdir -m 700 "$VIBECAF_STATE_DIR/session"
printf '1\n' > "$MOCK_PMSET_STATE"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]

# An abandoned pre-activation claim is cleared while sleep is still normal. It
# must not be mistaken for ownership if another tool blocks sleep later.
printf '0\n' > "$MOCK_PMSET_STATE"
printf 'abandoned\n' > "$VIBECAF_STATE_DIR/session/id"
printf 'enabling\n' > "$VIBECAF_STATE_DIR/session/state"
now=$(date +%s)
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/started_at"
printf '%s\n' "$((now + 21600))" > "$VIBECAF_STATE_DIR/session/deadline"
printf '21600\n' > "$VIBECAF_STATE_DIR/session/duration_seconds"
printf '20\n' > "$VIBECAF_STATE_DIR/session/battery_floor"
printf '1\n' > "$VIBECAF_STATE_DIR/session/recovery"
printf '0\n' > "$VIBECAF_STATE_DIR/session/notifications"
printf '999999\n' > "$VIBECAF_STATE_DIR/session/enabling_pid"
printf 'not-a-start\n' > "$VIBECAF_STATE_DIR/session/enabling_start"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]
printf '1\n' > "$MOCK_PMSET_STATE"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]

echo "thermal and crash recovery: ok"
