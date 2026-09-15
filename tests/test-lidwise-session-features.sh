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

# Defaults and next-session power policy are explicit and validated.
config=$($VIBECAF config get --json)
[ "$(printf '%s' "$config" | plutil -extract battery_floor raw -o - -)" = 20 ]
[ "$(printf '%s' "$config" | plutil -extract require_ac raw -o - -)" = false ]
$VIBECAF config set battery-floor 035 >/dev/null
$VIBECAF config set require-ac on >/dev/null
! $VIBECAF config set battery-floor 0 >/dev/null 2>&1
! $VIBECAF config set battery-floor 101 >/dev/null 2>&1
! $VIBECAF config set battery-floor 9999999999999999999 >/dev/null 2>&1
! $VIBECAF config set require-ac maybe >/dev/null 2>&1
! env MOCK_POWER_SOURCE='Battery Power' MOCK_BATTERY_PCT=80 $VIBECAF on --for 600 >/dev/null 2>&1
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]

# A session snapshots its policy. Later config changes affect only the next session.
$VIBECAF on --for 600 >/dev/null
[ "$(cat "$VIBECAF_STATE_DIR/session/battery_floor")" = 35 ]
[ "$(cat "$VIBECAF_STATE_DIR/session/require_ac")" = 1 ]
$VIBECAF config set battery-floor 10 >/dev/null
$VIBECAF config set require-ac off >/dev/null
status=$($VIBECAF status --json)
[ "$(printf '%s' "$status" | plutil -extract battery_floor raw -o - -)" = 35 ]
[ "$(printf '%s' "$status" | plutil -extract default_battery_floor raw -o - -)" = 10 ]
[ "$(printf '%s' "$status" | plutil -extract require_ac raw -o - -)" = true ]
[ "$(printf '%s' "$status" | plutil -extract default_require_ac raw -o - -)" = false ]
[ "$(printf '%s' "$status" | plutil -extract can_extend raw -o - -)" = true ]

# The warning is once per deadline. An explicit extension rearms it.
started=$(cat "$VIBECAF_STATE_DIR/session/started_at")
printf '%s\n' "$((started + 240))" > "$VIBECAF_STATE_DIR/session/deadline"
: > "$VIBECAF_NOTIFY_LOG"
$VIBECAF __guard_once
$VIBECAF __guard_once
[ "$(grep -c '^Awake session ending soon' "$VIBECAF_NOTIFY_LOG")" -eq 1 ]
deadline=$(cat "$VIBECAF_STATE_DIR/session/deadline")
$VIBECAF extend --by 30 >/dev/null
[ "$(cat "$VIBECAF_STATE_DIR/session/deadline")" -eq $((deadline + 30)) ]
$VIBECAF __guard_once
[ "$(grep -c '^Awake session ending soon' "$VIBECAF_NOTIFY_LOG")" -eq 2 ]

# Concurrent extension mutations serialize and the six-hour cap rejects without mutation.
deadline=$(cat "$VIBECAF_STATE_DIR/session/deadline")
$VIBECAF extend --by 20 >/dev/null & first=$!
$VIBECAF extend --by 20 >/dev/null & second=$!
wait "$first"; wait "$second"
[ "$(cat "$VIBECAF_STATE_DIR/session/deadline")" -eq $((deadline + 40)) ]
deadline=$(cat "$VIBECAF_STATE_DIR/session/deadline")
! $VIBECAF extend --by 21600 >/dev/null 2>&1
[ "$(cat "$VIBECAF_STATE_DIR/session/deadline")" = "$deadline" ]

# The active charging-only policy is enforced even after the default changes.
env MOCK_POWER_SOURCE='Battery Power' MOCK_BATTERY_PCT=80 $VIBECAF __guard_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
history=$($VIBECAF history --json)
[ "$(printf '%s' "$history" | plutil -extract sessions.0.reason raw -o - -)" = 'AC power is required for this session' ]
[ "$(printf '%s' "$history" | plutil -extract sessions.0.restoration raw -o - -)" = verified ]

# Failed restoration remains visible and is replaced by verified recovery for the same session.
$VIBECAF on --for 600 >/dev/null
id=$(cat "$VIBECAF_STATE_DIR/session/id")
! env MOCK_PMSET_SET0_FAIL=1 MOCK_BATTERY_PCT=0 VIBECAF_NONINTERACTIVE=1 $VIBECAF off >/dev/null 2>&1
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract sessions.0.session_id raw -o - -)" = "$id" ]
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract sessions.0.restoration raw -o - -)" = failed ]
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract sessions.0.battery_end raw -o - -)" = 0 ]
$VIBECAF off >/dev/null
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract sessions.0.restoration raw -o - -)" = verified ]
[ "$(grep -c "^$id" "$VIBECAF_STATE_DIR/history.tsv")" -eq 1 ]

# Oversized malformed history is ignored and cannot prevent verified restoration.
$VIBECAF on --for 600 >/dev/null
dd if=/dev/zero bs=70000 count=1 2>/dev/null | tr '\0' x > "$VIBECAF_STATE_DIR/history.tsv"
chmod 600 "$VIBECAF_STATE_DIR/history.tsv"
$VIBECAF off >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ "$(wc -c < "$VIBECAF_STATE_DIR/history.tsv")" -lt 65536 ]
printf 'bad\trow\n' >> "$VIBECAF_STATE_DIR/history.tsv"
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract schema_version raw -o - -)" = 1 ]

# Readers and upsert inspect at most 40 raw rows, including invalid rows.
: > "$VIBECAF_STATE_DIR/history.tsv"
for n in $(seq 1 40); do printf 'a\t1\t2\t3\tx\tverified\t-\t-\tAC\tbad\n'; done >> "$VIBECAF_STATE_DIR/history.tsv"
printf 'late-valid\t1\t2\t3\tlate record\tverified\t-\t-\tAC\tAC\n' >> "$VIBECAF_STATE_DIR/history.tsv"
chmod 600 "$VIBECAF_STATE_DIR/history.tsv"
history=$($VIBECAF history --json)
! printf '%s' "$history" | grep -q 'late-valid'
status=$($VIBECAF status --json)
printf '%s' "$status" | grep -q '"last_session":null'

# A dense under-size invalid file cannot delay or prevent sleep restoration.
$VIBECAF on --for 600 >/dev/null
id=$(cat "$VIBECAF_STATE_DIR/session/id")
: > "$VIBECAF_STATE_DIR/history.tsv"
for n in $(seq 1 1800); do printf 'a\t1\t2\t3\tx\tverified\t-\t-\tAC\tbad\n'; done >> "$VIBECAF_STATE_DIR/history.tsv"
chmod 600 "$VIBECAF_STATE_DIR/history.tsv"
[ "$(wc -c < "$VIBECAF_STATE_DIR/history.tsv")" -lt 65536 ]
$VIBECAF status --json | plutil -extract schema_version raw -o - - | grep -q '^1$'
$VIBECAF off >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ "$(wc -l < "$VIBECAF_STATE_DIR/history.tsv")" -eq 1 ]
[ "$(printf '%s' "$($VIBECAF history --json)" | plutil -extract sessions.0.session_id raw -o - -)" = "$id" ]

# History is bounded to 20 valid records and accepts an explicit unknown result.
USER_ID=$(id -u) PS=/bin/ps SELF="$VIBECAF" DEFAULT_DURATION=21600 DEFAULT_BATTERY_FLOOR=20
RUNTIME_DIR=$VIBECAF_RUNTIME_DIR STATE_DIR=$VIBECAF_STATE_DIR SESSION_DIR="$STATE_DIR/session" CONFIG_DIR="$STATE_DIR/config"
GOALS_DIR="$STATE_DIR/goals" AGENTS_DIR="$STATE_DIR/agents" LOG_DIR="$STATE_DIR/logs"
source "$ROOT/lib/lidwise/session.sh"
source "$ROOT/lib/lidwise/history.sh"
for n in $(seq 1 25); do history_upsert "history-$n" 100 200 150 "test $n" unknown - - AC AC; done
history=$($VIBECAF history --json)
[ "$(wc -l < "$VIBECAF_STATE_DIR/history.tsv")" -eq 20 ]
[ "$(printf '%s' "$history" | plutil -extract sessions.0.session_id raw -o - -)" = history-25 ]
[ "$(printf '%s' "$history" | plutil -extract sessions.0.restoration raw -o - -)" = unknown ]

# CLI helper routing is transparent and preserves helper exit status.
cat > "$TEST_ROOT/bin/scanner" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$TEST_ROOT/scanner-args"
exit "${MOCK_HELPER_EXIT:-0}"
MOCK
cat > "$TEST_ROOT/bin/probe" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$TEST_ROOT/probe-args"
exit "${MOCK_HELPER_EXIT:-0}"
MOCK
chmod 0755 "$TEST_ROOT/bin/scanner" "$TEST_ROOT/bin/probe"
env VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/bin/scanner" $VIBECAF hooks preview claude --json
[ "$(cat "$TEST_ROOT/scanner-args")" = '--hooks preview claude --json' ]
env VIBECAF_LID_PROBE_CMD="$TEST_ROOT/bin/probe" $VIBECAF verify --expect sleep --seconds 15 --json
[ "$(cat "$TEST_ROOT/probe-args")" = '--expect sleep --seconds 15 --json' ]
! env MOCK_HELPER_EXIT=7 VIBECAF_LID_PROBE_CMD="$TEST_ROOT/bin/probe" $VIBECAF verify >/dev/null 2>&1

echo "session extension, warnings, policies, history, and dispatch: ok"
