#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-state-machines.XXXXXX")
export TEST_ROOT
cleanup() {
  for f in "$VIBECAF_RUNTIME_DIR"/*.pid; do [ -f "$f" ] && kill "$(cut -d'|' -f1 "$f")" 2>/dev/null || true; done
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
printf '0\n' > "$MOCK_PMSET_STATE"; printf 'nominal\n' > "$MOCK_THERMAL_STATE"
: > "$MOCK_PMSET_LOG"; : > "$VIBECAF_NOTIFY_LOG"
session="$VIBECAF_STATE_DIR/session"
fail() { echo "FAIL: $*" >&2; exit 1; }

# SM-1: an activation that died after pmset 1 is recovered at once, not
# reported as a failed recovery until the activation grace expires.
$VIBECAF on >/dev/null
printf 'enabling\n' > "$session/state"; printf '999999\n' > "$session/enabling_pid"; printf 'x\n' > "$session/enabling_start"
date +%s > "$session/started_at"
$VIBECAF __guardian_once || fail "guardian did not recover a dead activation"
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ] || fail "sleep still blocked after dead activation"
! grep -q 'Crash recovery failed' "$VIBECAF_NOTIFY_LOG" || fail "false crash-recovery alert"
grep -q $'Awake mode recovered\tsession activation did not finish' "$VIBECAF_NOTIFY_LOG"
: > "$VIBECAF_NOTIFY_LOG"

# SM-2: an activation that completes between the guardian's unlocked
# observation and its action is left alone: no alert, readiness kept.
$VIBECAF on >/dev/null
id=$(cat "$session/id")
printf 'enabling\n' > "$session/state"; printf '999999\n' > "$session/enabling_pid"; printf 'x\n' > "$session/enabling_start"
cat > "$TEST_ROOT/bin/ps-race" <<'MOCK'
#!/bin/bash
# First process lookup "finishes" the activation, as a racing enabler would.
if [ -f "$RACE_TRIGGER" ]; then rm -f "$RACE_TRIGGER"
  printf 'active\n' > "$RACE_SESSION/state"; rm -f "$RACE_SESSION/enabling_pid" "$RACE_SESSION/enabling_start"
fi
exec /bin/ps "$@"
MOCK
chmod 755 "$TEST_ROOT/bin/ps-race"; : > "$TEST_ROOT/race-trigger"
RACE_TRIGGER="$TEST_ROOT/race-trigger" RACE_SESSION="$session" VIBECAF_PS="$TEST_ROOT/bin/ps-race" $VIBECAF __guardian_once
[ ! -e "$TEST_ROOT/race-trigger" ] || fail "race trigger never fired"
[ "$(cat "$MOCK_PMSET_STATE")" = 1 ] || fail "healthy session was turned off by a stale observation"
[ "$(cat "$session/id")" = "$id" ]
[ -e "$session/recovery_verified_at" ] || fail "stale observation invalidated readiness"
[ ! -s "$VIBECAF_NOTIFY_LOG" ] || fail "stale observation sent: $(cat "$VIBECAF_NOTIFY_LOG")"
$VIBECAF off >/dev/null

# SM-3: on does not retain an expired session as "on"; it replaces it.
$VIBECAF on --for 600 >/dev/null
old=$(cat "$session/id")
printf '%s\n' "$(($(date +%s) - 1))" > "$session/deadline"
sleep 1
$VIBECAF on --for 600 > "$TEST_ROOT/on-out"
! grep -q 'Existing session retained' "$TEST_ROOT/on-out" || fail "expired session was retained"
[ "$(cat "$session/id")" != "$old" ]
$VIBECAF history --json | grep -q '"reason":"session deadline passed"'
$VIBECAF off >/dev/null


# SM-4: a guard exits once its session is gone, even under another sleep block.
VIBECAF_GUARD_EVERY=1 $VIBECAF on >/dev/null
guard=$(cut -d'|' -f1 "$VIBECAF_RUNTIME_DIR/guard.pid")
caf=$(cut -d'|' -f1 "$VIBECAF_RUNTIME_DIR/caffeinate.pid")
printf 'other\n' > "$session/id"   # session replaced; sleep stays blocked
for _ in $(seq 1 40); do kill -0 "$guard" 2>/dev/null || break; sleep 0.1; done
! kill -0 "$guard" 2>/dev/null || { kill "$guard"; fail "guard outlived its session"; }
kill "$caf" 2>/dev/null || true
printf '0\n' > "$MOCK_PMSET_STATE"; rm -f "$session"/* "$VIBECAF_RUNTIME_DIR"/*.pid

# SM-5: the guard wakes at the deadline rather than a full interval later.
# (No guardian runs here, so on itself returns after its bounded 3s wait.)
$VIBECAF on --for 2 >/dev/null &
for _ in $(seq 1 60); do [ "$(cat "$MOCK_PMSET_STATE")" = 1 ] && [ -s "$VIBECAF_RUNTIME_DIR/guard.pid" ] && break; sleep 0.1; done
sm5_guard=$(cut -d'|' -f1 "$VIBECAF_RUNTIME_DIR/guard.pid" 2>/dev/null || true)
for _ in $(seq 1 45); do [ "$(cat "$MOCK_PMSET_STATE")" = 0 ] && break; sleep 0.1; done
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ] || fail "deadline was not enforced on time (guard interval 3600s)"
wait
$VIBECAF history --json | grep -q '"reason":"session deadline passed"'
sleep 0.5
[ -n "$sm5_guard" ] || fail "SM-5 guard was not recorded"
! kill -0 "$sm5_guard" 2>/dev/null || { kill "$sm5_guard"; fail "guard lingered after ending its session"; }

# INV-1: a settings directory that lost its private mode is repaired, not
# silently read as defaults; an unrepairable one makes on fail closed.
$VIBECAF config set require-ac on >/dev/null
chmod 755 "$VIBECAF_STATE_DIR/config"
$VIBECAF config get --json | grep -q '"require_ac":true' || fail "config mode change reset policy"
[ "$(stat -f %Lp "$VIBECAF_STATE_DIR/config")" = 700 ]
MOCK_POWER_SOURCE='Battery Power' MOCK_BATTERY_PCT=50 $VIBECAF on >/dev/null 2>&1 && fail "require-ac ignored"
$VIBECAF config set require-ac off >/dev/null
mv "$VIBECAF_STATE_DIR/config" "$TEST_ROOT/config-real"; ln -s "$TEST_ROOT/config-real" "$VIBECAF_STATE_DIR/config"
! $VIBECAF on > "$TEST_ROOT/untrusted" 2>&1 || fail "on ran with an untrusted settings directory"
grep -q 'not private' "$TEST_ROOT/untrusted"
[ "$(cat "$MOCK_PMSET_STATE")" = 0 ]
rm "$VIBECAF_STATE_DIR/config"; mv "$TEST_ROOT/config-real" "$VIBECAF_STATE_DIR/config"

# INV-2: a history file that lost its mode keeps its rows.
$VIBECAF on >/dev/null; $VIBECAF off >/dev/null
before=$($VIBECAF history --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["sessions"]))')
chmod 644 "$VIBECAF_STATE_DIR/history.tsv"
$VIBECAF on >/dev/null; $VIBECAF off >/dev/null
after=$($VIBECAF history --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["sessions"]))')
[ "$after" -eq $((before + 1)) ] || fail "history rows lost ($before -> $after)"

# A busy lock alone does not withdraw readiness from a healthy session; the
# failure is recorded only when a stop condition is due (see test-lidwise-core).
$VIBECAF on >/dev/null
printf '#!/bin/bash\nexit 75\n' > "$TEST_ROOT/bin/lockf-busy"; chmod 755 "$TEST_ROOT/bin/lockf-busy"
VIBECAF_LOCKF="$TEST_ROOT/bin/lockf-busy" $VIBECAF __guard_once >/dev/null 2>&1 || true
[ -e "$session/recovery_verified_at" ] || fail "busy lock marked a healthy session unverified"
doctor_out=$($VIBECAF doctor); grep -q "^recovery ready: " <<< "$doctor_out" || fail "doctor does not report readiness"
$VIBECAF off >/dev/null

# Activation latency: with a running guardian, on returns acknowledged quickly.
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF __guardian >/dev/null 2>&1 & echo "$!" >> "$TEST_ROOT/pids"
for _ in $(seq 1 50); do [ -p "$VIBECAF_RUNTIME_DIR/guardian.doorbell" ] && break; sleep 0.1; done
sleep 1.2   # let the guardian reach its idle wait
start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF on >/dev/null
end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF status --json | grep -q '"recovery_ready":true' || fail "guardian did not acknowledge activation"
python3 -c "import sys; d=$end-$start; print('activation: %.2fs' % d); sys.exit(0 if d < 1.5 else 1)" || fail "activation too slow"
$VIBECAF off >/dev/null

echo 'state machine and persisted-invariant regressions: PASS'
