#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-core.XXXXXX")
sleeper=""; orphan=""; activator=""; protected_root=""; protected_child=""; guardian=""
cleanup() {
  [ -z "$guardian" ] || kill "$guardian" 2>/dev/null || true
  [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null || true
  [ -z "$orphan" ] || kill "$orphan" 2>/dev/null || true
  if [ -n "$activator" ]; then kill -CONT "$activator" 2>/dev/null || true; kill "$activator" 2>/dev/null || true; fi
  [ -z "$protected_root" ] || kill -CONT "$protected_root" 2>/dev/null || true
  [ -z "$protected_root" ] || kill "$protected_root" 2>/dev/null || true
  [ -z "$protected_child" ] || kill "$protected_child" 2>/dev/null || true
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
export VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/bin/missing-scanner"
export VIBECAF_NO_NETWATCH=1
export MOCK_PMSET_STATE="$TEST_ROOT/pmset-state"
export MOCK_PMSET_LOG="$TEST_ROOT/pmset.log"
export MOCK_THERMAL_STATE="$TEST_ROOT/thermal-state"
mkdir -p "$TEST_ROOT/bin" "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR"

cat > "$VIBECAF_PMSET" <<'MOCK'
#!/bin/bash
set -u
case "$*" in
  "-g") [ "${MOCK_PMSET_QUERY_FAIL:-0}" = 1 ] && exit 1; printf 'System-wide power settings:\n SleepDisabled %s\n' "$(cat "$MOCK_PMSET_STATE")" ;;
  "-g batt") printf "Now drawing from '%s'\n -InternalBattery-0 %s%%; charged\n" "${MOCK_POWER_SOURCE:-AC Power}" "${MOCK_BATTERY_PCT:-100}" ;;
  "-a disablesleep "*)
    value=$3; printf '%s\n' "$value" >> "$MOCK_PMSET_LOG"
    [ "$value" = 1 ] && [ "${MOCK_PMSET_SET1_DELAY:-0}" != 0 ] && sleep "$MOCK_PMSET_SET1_DELAY"
    [ "$value" = 0 ] && [ "${MOCK_PMSET_SET0_FAIL:-0}" = 1 ] && exit 1
    [ "$value" = 1 ] && [ "${MOCK_PMSET_SET1_FAIL:-0}" = 1 ] && exit 1
    [ "$value" = 1 ] && [ "${MOCK_PMSET_IGNORE_SET1:-0}" = 1 ] && exit 0
    printf '%s\n' "$value" > "$MOCK_PMSET_STATE"
    [ "$value" = 1 ] && [ "${MOCK_PMSET_SET1_POST_DELAY:-0}" != 0 ] && sleep "$MOCK_PMSET_SET1_POST_DELAY"
    : ;;
  *) exit 2 ;;
esac
MOCK
cat > "$VIBECAF_SUDO" <<'MOCK'
#!/bin/bash
set -u
[ "${MOCK_SUDO_FAIL:-0}" = 1 ] && exit 1
seen_k=0
list_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in -n) shift ;; -k) seen_k=1; shift ;; -l|-ll) list_only=1; shift ;; --) shift; break ;; *) break ;; esac
done
[ "$seen_k" = 1 ] && [ "${MOCK_SUDO_ALLOW_K:-1}" = 0 ] && exit 1
if [ "$list_only" = 1 ]; then
  [ "${MOCK_SUDO_LIST_FAIL:-0}" = 1 ] && exit 1
  printf '%s\n' "${MOCK_SUDO_LIST_OUTPUT:-Options: !authenticate}"
  exit 0
fi
exec "$@"
MOCK
cat > "$VIBECAF_OSASCRIPT" <<'MOCK'
#!/bin/bash
exit 1
MOCK
cat > "$VIBECAF_LAUNCHCTL" <<'MOCK'
#!/bin/bash
[ "${MOCK_GUARDIAN_RUNNING:-1}" = 1 ]
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

# A live descendant that cannot be signaled is not mistaken for an exited
# process, and takeover leaves the recorded root alive for a later retry.
USER_ID=$(id -u); PS=/bin/ps; RUNTIME_DIR=$VIBECAF_RUNTIME_DIR
source "$ROOT/lib/lidwise/session.sh"
/bin/bash -c 'sleep 30 & echo "$!" > "$1"; wait' helper "$TEST_ROOT/protected-child" 9>&- & protected_root=$!
while [ ! -s "$TEST_ROOT/protected-child" ]; do sleep 0.01; done
protected_child=$(cat "$TEST_ROOT/protected-child")
protected_start=$(process_start_identity "$protected_root")
kill() {
  if [ "${1:-}" = -STOP ] && [ "${2:-}" = "$protected_child" ]; then return 1; fi
  builtin kill "$@"
}
! quiesce_process_tree "$protected_root" "$protected_start"
process_identity_same "$protected_child" "$(process_start_identity "$protected_child")"
process_identity_same "$protected_root" "$protected_start"
unset -f kill
builtin kill -TERM "$protected_root" "$protected_child" 2>/dev/null || true
wait "$protected_root" 2>/dev/null || true
protected_root=""; protected_child=""

VIBECAF="$ROOT/bin/lidwise"
printf '0\n' > "$MOCK_PMSET_STATE"
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
: > "$MOCK_PMSET_LOG"

# The off-state JSON contract is complete, ordered, valid, and explicit.
json=$($VIBECAF status --json)
[ "$(printf '%s' "$json" | /usr/bin/plutil -extract schema_version raw -o - -)" = 1 ]
normalized=$(printf '%s' "$json" | sed -E 's/"observed_at":[0-9]+/"observed_at":TIME/')
expected='{"schema_version":1,"phase":"off","session_id":null,"started_at":null,"deadline":null,"remaining_seconds":null,"duration_seconds":21600,"default_duration_seconds":21600,"battery_floor":20,"default_battery_floor":20,"require_ac":false,"default_require_ac":false,"can_extend":false,"power_source":"AC","battery_percent":100,"thermal":"nominal","guard_running":false,"guardian_running":true,"recovery_ready":false,"recovery_authorized_at":null,"recovery_authorization_current":false,"issues":[],"network_state":"unknown","network_detail":"Not checked","network_recovery":true,"network_recovery_available":false,"agent_notifications":false,"agents":{"claude":{"working":0,"waiting":0,"quiet":0,"finished":0,"failed":0},"codex":{"working":0,"waiting":0,"quiet":0,"finished":0,"failed":0}},"goals":{"active":0,"stalled":0,"completed":0,"failed":0},"last_session":null,"observed_at":TIME}'
[ "$normalized" = "$expected" ]

# Settings persist privately and reject malformed or out-of-range input.
$VIBECAF config set duration 09 >/dev/null
[ "$($VIBECAF config get --json | /usr/bin/plutil -extract duration_seconds raw -o - -)" = 9 ]
$VIBECAF config set duration 90 >/dev/null
$VIBECAF config set recovery off >/dev/null
$VIBECAF config set notifications on >/dev/null
config=$($VIBECAF config get --json)
[ "$config" = '{"schema_version":1,"duration_seconds":90,"battery_floor":20,"require_ac":false,"network_recovery":false,"agent_notifications":true}' ]
[ "$(stat -f %Lp "$VIBECAF_STATE_DIR/config")" = 700 ]
[ "$(stat -f %Lp "$VIBECAF_STATE_DIR/config/duration")" = 600 ]
! $VIBECAF config set duration 0 >/dev/null 2>&1
! $VIBECAF config set duration 21601 >/dev/null 2>&1
! $VIBECAF config set duration 999999999999999999999999 >/dev/null 2>&1
! $VIBECAF config set duration nope >/dev/null 2>&1
! $VIBECAF config set recovery maybe >/dev/null 2>&1
! $VIBECAF on --for 0 >/dev/null 2>&1

# Refuse mutation when the OS lock utility lacks file-descriptor mode.
cat > "$TEST_ROOT/bin/lockf-unsupported" <<'MOCK'
#!/bin/bash
exit 64
MOCK
chmod 0755 "$TEST_ROOT/bin/lockf-unsupported"
! env VIBECAF_LOCKF="$TEST_ROOT/bin/lockf-unsupported" $VIBECAF config set duration 60 >"$TEST_ROOT/lockf-out" 2>&1
grep -q 'does not support the required kernel lock mode' "$TEST_ROOT/lockf-out"
[ "$($VIBECAF config get --json | /usr/bin/plutil -extract duration_seconds raw -o - -)" = 90 ]

# Activation requires durable, cache-independent recovery authorization.
! env MOCK_SUDO_ALLOW_K=0 $VIBECAF on --for 60 >/dev/null 2>&1
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]
! grep -q '^1$' "$MOCK_PMSET_LOG"

before=$(wc -l < "$MOCK_PMSET_LOG")
! env MOCK_GUARDIAN_RUNNING=0 $VIBECAF on --for 60 >/dev/null 2>&1
printf 'serious\n' > "$MOCK_THERMAL_STATE"
! $VIBECAF on --for 60 >/dev/null 2>&1
printf 'nominal\n' > "$MOCK_THERMAL_STATE"
! env MOCK_POWER_SOURCE='Battery Power' MOCK_BATTERY_PCT=20 $VIBECAF on --for 60 >/dev/null 2>&1
! env MOCK_PMSET_QUERY_FAIL=1 $VIBECAF toggle >/dev/null 2>&1
[ "$(wc -l < "$MOCK_PMSET_LOG")" -eq "$before" ]
env MOCK_PMSET_QUERY_FAIL=1 $VIBECAF status --json | grep -q '"phase":"unknown"'

# A failed durable write prevents activation.
mkdir "$TEST_ROOT/foreign-session"
rmdir "$VIBECAF_STATE_DIR/session"
ln -s "$TEST_ROOT/foreign-session" "$VIBECAF_STATE_DIR/session"
! $VIBECAF on --for 60 >/dev/null 2>&1
rm "$VIBECAF_STATE_DIR/session"
mkdir -m 700 "$VIBECAF_STATE_DIR/session"
! grep -q '^1$' "$MOCK_PMSET_LOG"

$VIBECAF config set recovery on >/dev/null
$VIBECAF config set notifications off >/dev/null
$VIBECAF on --for 60 >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 1 ]
id=$(cat "$VIBECAF_STATE_DIR/session/id")
deadline=$(cat "$VIBECAF_STATE_DIR/session/deadline")
started=$(cat "$VIBECAF_STATE_DIR/session/started_at")
[ $((deadline - started)) -eq 60 ]
[ "$(stat -f %Lp "$VIBECAF_RUNTIME_DIR")" = 700 ]
[ "$(stat -f %Lp "$VIBECAF_RUNTIME_DIR/caffeinate.pid")" = 600 ]
$VIBECAF __guardian_once
$VIBECAF status --json | grep -q '"recovery_ready":true'
env MOCK_SUDO_LIST_FAIL=1 $VIBECAF status --json | grep -q '"recovery_authorization_current":false'
env MOCK_SUDO_LIST_OUTPUT='Options: authenticate' $VIBECAF status --json | grep -q '"recovery_authorization_current":false'

# A failed automatic off attempt invalidates readiness even before it can
# acquire the mutation lock.
cat > "$TEST_ROOT/bin/lockf-busy" <<'MOCK'
#!/bin/bash
exit 75
MOCK
chmod 0755 "$TEST_ROOT/bin/lockf-busy"
printf 'critical\n' > "$MOCK_THERMAL_STATE"
env VIBECAF_LOCKF="$TEST_ROOT/bin/lockf-busy" $VIBECAF __guard_once >/dev/null 2>&1 || true
[ "$(cat "$MOCK_PMSET_STATE")" = 1 ]
[ ! -e "$VIBECAF_STATE_DIR/session/recovery_verified_at" ]
[ ! -e "$VIBECAF_STATE_DIR/session/recovery_verified_session" ]
$VIBECAF status --json | grep -q '"recovery_ready":false'
printf 'nominal\n' > "$MOCK_THERMAL_STATE"

# A repeated on is idempotent, even after authorization is lost.
MOCK_SUDO_FAIL=1 $VIBECAF on --for 120 | grep -q 'deadline was not extended'
[ "$(cat "$VIBECAF_STATE_DIR/session/id")" = "$id" ]
[ "$(cat "$VIBECAF_STATE_DIR/session/deadline")" = "$deadline" ]

# Failed restoration retains ownership and the live safety guard.
guard_pid=$(cut -d'|' -f1 "$VIBECAF_RUNTIME_DIR/guard.pid")
! env MOCK_PMSET_SET0_FAIL=1 VIBECAF_NONINTERACTIVE=1 $VIBECAF off >/dev/null 2>&1
[ "$(cat "$MOCK_PMSET_STATE")" = 1 ]
[ "$(cat "$VIBECAF_STATE_DIR/session/id")" = "$id" ]
kill -0 "$guard_pid"
$VIBECAF status --json | grep -q '"recovery_authorized_at":null'
$VIBECAF off >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]

# External ownership is explicit and protected without --force.
printf '1\n' > "$MOCK_PMSET_STATE"
$VIBECAF status --json | grep -q '"phase":"external-on"'
! $VIBECAF off >/dev/null 2>&1
! $VIBECAF toggle >/dev/null 2>&1
[ "$(cat "$MOCK_PMSET_STATE")" = 1 ]
$VIBECAF off --force >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]

# A successful command is not reported when pmset ignores the requested state.
! env MOCK_PMSET_IGNORE_SET1=1 $VIBECAF on --for 60 >/dev/null 2>&1
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]

# A frozen activator cannot hold the recovery lock past its deadline.
env MOCK_PMSET_SET1_POST_DELAY=10 $VIBECAF on --for 1 > "$TEST_ROOT/frozen-on" 2>&1 & activator=$!
while [ "$(cat "$MOCK_PMSET_STATE")" != 1 ]; do sleep .01; done
kill -STOP "$activator"
sleep 1
env VIBECAF_ACTIVATION_GRACE=1 $VIBECAF __guardian_once
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]
kill -CONT "$activator" 2>/dev/null || true
wait "$activator" 2>/dev/null || true
activator=""

# Optional policy corruption remains visibly owned and is recovered safely.
now=$(date +%s)
printf '1\n' > "$MOCK_PMSET_STATE"
printf 'policy-test\n' > "$VIBECAF_STATE_DIR/session/id"
printf 'active\n' > "$VIBECAF_STATE_DIR/session/state"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/started_at"
printf '%s\n' "$((now + 60))" > "$VIBECAF_STATE_DIR/session/deadline"
printf '60\n' > "$VIBECAF_STATE_DIR/session/duration_seconds"
printf '20\n' > "$VIBECAF_STATE_DIR/session/battery_floor"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/heartbeat"
$VIBECAF status --json | grep -q '"phase":"owned-on"'
$VIBECAF off >/dev/null

# A legacy owned record remains owned and can be restored safely.
now=$(date +%s)
printf '1\n' > "$MOCK_PMSET_STATE"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/owned"
printf 'active\n' > "$VIBECAF_STATE_DIR/session/active"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/started"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/heartbeat"
printf '%s\n' "$((now + 60))" > "$VIBECAF_STATE_DIR/session/deadline"
$VIBECAF status --json | grep -q '"session_id":"legacy-'
$VIBECAF off >/dev/null
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]

# Expired legacy residue does not adopt a later external sleep block.
now=$(date +%s)
printf '1\n' > "$MOCK_PMSET_STATE"
printf '%s\n' "$((now - 120))" > "$VIBECAF_STATE_DIR/session/owned"
printf 'active\n' > "$VIBECAF_STATE_DIR/session/active"
printf '%s\n' "$((now - 120))" > "$VIBECAF_STATE_DIR/session/started"
printf '%s\n' "$((now - 120))" > "$VIBECAF_STATE_DIR/session/heartbeat"
printf '%s\n' "$((now - 60))" > "$VIBECAF_STATE_DIR/session/deadline"
$VIBECAF status --json | grep -q '"phase":"external-on"'
! $VIBECAF off >/dev/null 2>&1
printf '0\n' > "$MOCK_PMSET_STATE"
$VIBECAF off >/dev/null
[ ! -e "$VIBECAF_STATE_DIR/session/owned" ]

# Incomplete ownership residue is neither adopted nor discarded as external.
printf '1\n' > "$MOCK_PMSET_STATE"
printf '%s\n' "$now" > "$VIBECAF_STATE_DIR/session/owned"
$VIBECAF status --json | grep -q '"phase":"unknown".*"Session ownership record is incomplete"'
! $VIBECAF __maintenance --remove -- /usr/bin/true >/dev/null 2>&1
printf '0\n' > "$MOCK_PMSET_STATE"
$VIBECAF off >/dev/null
[ ! -e "$VIBECAF_STATE_DIR/session/owned" ]
printf 'partial-modern\n' > "$VIBECAF_STATE_DIR/session/id"
$VIBECAF __guardian_once
[ ! -e "$VIBECAF_STATE_DIR/session/id" ]

# Concurrent on/on serializes to one activation and one unchanged deadline.
: > "$MOCK_PMSET_LOG"
MOCK_PMSET_SET1_DELAY=.2 $VIBECAF on --for 60 > "$TEST_ROOT/on-one" & one=$!
MOCK_PMSET_SET1_DELAY=.2 $VIBECAF on --for 120 > "$TEST_ROOT/on-two" & two=$!
wait "$one"; wait "$two"
[ "$(grep -c '^1$' "$MOCK_PMSET_LOG")" -eq 1 ]
started=$(cat "$VIBECAF_STATE_DIR/session/started_at"); deadline=$(cat "$VIBECAF_STATE_DIR/session/deadline")
case $((deadline - started)) in 60|120) ;; *) exit 1 ;; esac

# An off command waits for an in-flight activation and runs after it.
$VIBECAF off >/dev/null
: > "$MOCK_PMSET_LOG"
MOCK_PMSET_SET1_DELAY=.2 $VIBECAF on --for 60 > "$TEST_ROOT/on-then-off" & one=$!
while ! grep -q '^1$' "$MOCK_PMSET_LOG" 2>/dev/null; do sleep .01; done
$VIBECAF off >/dev/null
wait "$one"
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]

# Start one more owned session for the reused-PID check.
$VIBECAF on --for 60 >/dev/null

# A forged reused PID record never signals an unrelated process.
orphan=$(cut -d'|' -f1 "$VIBECAF_RUNTIME_DIR/caffeinate.pid")
sleep 30 & sleeper=$!
start=$(/bin/ps -p "$sleeper" -o lstart= | awk '{$1=$1;print}')
printf '%s|caffeinate|%s|%s\n' "$sleeper" "$(cat "$VIBECAF_STATE_DIR/session/id")" "$start" > "$VIBECAF_RUNTIME_DIR/caffeinate.pid"
$VIBECAF off >/dev/null
kill -0 "$sleeper"
kill "$sleeper"; wait "$sleeper" 2>/dev/null || true; sleeper=""
kill "$orphan" 2>/dev/null || true; orphan=""

# A precreated runtime symlink cannot inject files or permit activation.
mkdir "$TEST_ROOT/forged-runtime"
ln -s "$TEST_ROOT/forged-runtime" "$TEST_ROOT/runtime-link"
before=$(wc -l < "$MOCK_PMSET_LOG")
! env VIBECAF_RUNTIME_DIR="$TEST_ROOT/runtime-link" $VIBECAF on --for 60 >/dev/null 2>&1
[ "$(wc -l < "$MOCK_PMSET_LOG")" -eq "$before" ]
[ ! -e "$TEST_ROOT/forged-runtime/session.lock" ]

# Doctor is read-only and reports explicit state.
before=$(wc -l < "$MOCK_PMSET_LOG")
doctor_output=$($VIBECAF doctor)
grep -q '^power phase: off$' <<< "$doctor_output"
[ "$(wc -l < "$MOCK_PMSET_LOG")" -eq "$before" ]

# Failure cases: on/toggle return before a real guardian acknowledges activation;
# waiting under the mutation lock starves an off-state guardian. Power is mocked.
env MOCK_PMSET_SET1_DELAY=1 $VIBECAF on --for 60 > "$TEST_ROOT/activation-output" & activator=$!
for attempt in {1..80}; do [ ! -f "$VIBECAF_STATE_DIR/session/id" ] || break; sleep 0.05; done
$VIBECAF __guardian > "$TEST_ROOT/guardian-output" 2>&1 & guardian=$!
wait "$activator"; activator=""
json=$($VIBECAF status --json)
if ! grep -q '"recovery_ready":true' <<< "$json"; then
  echo "Activation acknowledgement failed: $json" >&2
  cat "$TEST_ROOT/guardian-output" >&2
  exit 1
fi
$VIBECAF off >/dev/null
$VIBECAF toggle >/dev/null
json=$($VIBECAF status --json)
if ! grep -q '"recovery_ready":true' <<< "$json"; then
  echo "Activation acknowledgement failed: $json" >&2
  cat "$TEST_ROOT/guardian-output" >&2
  exit 1
fi
$VIBECAF off >/dev/null
kill "$guardian"; wait "$guardian" 2>/dev/null || true; guardian=""
echo 'activation and toggle await guardian outside the session lock: ok'

# Maintenance holds the mutation lock and refuses non-off state.
$VIBECAF __maintenance -- /usr/bin/true
printf '1\n' > "$MOCK_PMSET_STATE"
! $VIBECAF __maintenance -- /usr/bin/true >/dev/null 2>&1
printf '0\n' > "$MOCK_PMSET_STATE"

echo "core ownership, JSON, config, and PID safety: ok"
