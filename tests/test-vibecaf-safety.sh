#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-safety.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
export VIBECAF_PMSET="$TEST_ROOT/bin/pmset"
export VIBECAF_SUDO="$TEST_ROOT/bin/sudo"
export VIBECAF_THERMAL_STATE_CMD="$TEST_ROOT/bin/thermal-state"
export MOCK_PMSET_STATE="$TEST_ROOT/pmset-state"
export MOCK_THERMAL_STATE="$TEST_ROOT/thermal-state"
mkdir -p "$HOME" "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR/session" "$TEST_ROOT/bin"

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
chmod 0755 "$VIBECAF_PMSET" "$VIBECAF_SUDO" "$VIBECAF_THERMAL_STATE_CMD"

VIBECAF="$ROOT/bin/vibecaf"

printf '0\n' > "$MOCK_PMSET_STATE"
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
grep -q '^AWAKE MODE: OFF$' <("$VIBECAF" status)

begin_fake_session() {
  local now
  now=$(date +%s)
  printf '1\n' > "$MOCK_PMSET_STATE"
  printf 'active\n' > "$VIBECAF_STATE_DIR/session/active"
  printf 'owned\n' > "$VIBECAF_STATE_DIR/session/owned"
  printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/started"
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
[ -e "$VIBECAF_STATE_DIR/session/owned" ]

# Corrupt durable timestamps fail safe instead of crashing the guardian.
begin_fake_session
printf 'not-a-time\n' > "$VIBECAF_STATE_DIR/session/heartbeat"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "0" ]

# Never undo another tool's disablesleep setting when this app has no durable
# ownership record.
rm -rf "$VIBECAF_STATE_DIR/session"
mkdir -p "$VIBECAF_STATE_DIR/session"
printf '1\n' > "$MOCK_PMSET_STATE"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]

# An abandoned pre-activation claim is cleared while sleep is still normal. It
# must not be mistaken for ownership if another tool blocks sleep later.
printf '0\n' > "$MOCK_PMSET_STATE"
printf '1\n' > "$VIBECAF_STATE_DIR/session/owned"
printf '999999\n' > "$VIBECAF_STATE_DIR/session/enabling-pid"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ ! -e "$VIBECAF_STATE_DIR/session/owned" ]
printf '1\n' > "$MOCK_PMSET_STATE"
VIBECAF_GUARDIAN_GRACE=10 "$VIBECAF" __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = "1" ]

echo "thermal and crash recovery: ok"
