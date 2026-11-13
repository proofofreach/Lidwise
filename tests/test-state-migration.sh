#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-state-migration.XXXXXX")
export TEST_ROOT
cleanup() {
  [ ! -s "$TEST_ROOT/pids" ] || while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$TEST_ROOT/pids"
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export HOME="$TEST_ROOT/home"; unset VIBECAF_STATE_DIR

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
mkdir -p "$TEST_ROOT/bin" "$VIBECAF_RUNTIME_DIR"
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
printf '0\n' > "$MOCK_PMSET_STATE"; printf 'nominal\n' > "$MOCK_THERMAL_STATE"; : > "$MOCK_PMSET_LOG"
fail() { echo "FAIL: $*" >&2; exit 1; }
AS="$HOME/Library/Application Support"; LEGACY="$AS/Closed-Lid Awake"; NEW="$AS/Lidwise"
mkdir -p "$AS"

# A fresh install uses the new folder.
$VIBECAF config set battery-floor 33 >/dev/null
[ -f "$NEW/config/battery-floor" ] && [ ! -e "$LEGACY" ] || fail "fresh install did not use $NEW"
mv "$NEW" "$LEGACY"

# Before migration, an existing install keeps using the old folder: no move
# outside the installer, and no split between CLI and guardian.
$VIBECAF config get --json | grep -q '"battery_floor":33' || fail "legacy settings not read"
$VIBECAF on >/dev/null; [ -f "$LEGACY/session/id" ] && [ ! -e "$NEW" ] || fail "session not in legacy folder"

# The installer's maintenance window never moves state under a live session.
! $VIBECAF __maintenance --migrate-state -- true >/dev/null 2>&1 || fail "maintenance ran during a session"
[ -d "$LEGACY/session" ] && [ ! -e "$NEW" ] || fail "state moved during a session"
$VIBECAF off >/dev/null

# A failed install leaves state in place.
$VIBECAF __maintenance --migrate-state -- false >/dev/null 2>&1 && fail "failed command reported success"
[ -d "$LEGACY" ] && [ ! -e "$NEW" ] || fail "state moved after a failed install"

# A running guardian follows the move and acknowledges the next session there.
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF __guardian >/dev/null 2>&1 & echo "$!" >> "$TEST_ROOT/pids"
sleep 1.5
out=$($VIBECAF __maintenance --migrate-state -- true)
grep -q "Moved settings and history" <<< "$out" || fail "migration did not report"
[ -d "$NEW" ] && [ ! -e "$LEGACY" ] || fail "state not moved"
[ "$(stat -f %Lp "$NEW")" = 700 ] || fail "moved folder not private"
$VIBECAF config get --json | grep -q '"battery_floor":33' || fail "settings lost in move"
$VIBECAF history --json | grep -q '"session_id"' || fail "history lost in move"
sleep 1.2
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF on >/dev/null
VIBECAF_GUARDIAN_EVERY=30 $VIBECAF status --json | grep -q '"recovery_ready":true' || fail "guardian did not follow the moved state"
[ "$(cat "$NEW/session/guardian_session")" = "$(cat "$NEW/session/id")" ]
$VIBECAF off >/dev/null

# A second run is a no-op; an old folder that reappears is ignored, not merged.
mkdir -m 700 "$LEGACY"; printf '99\n' > "$LEGACY/marker"
$VIBECAF __maintenance --migrate-state -- true >/dev/null
[ -f "$LEGACY/marker" ] && [ ! -e "$NEW/marker" ] || fail "reappeared old folder was merged"
doctor_out=$($VIBECAF doctor)
grep -q "state directory: ok ($NEW)" <<< "$doctor_out" || fail "doctor shows wrong state folder"
grep -q "old state folder (unused, safe to delete)" <<< "$doctor_out" || fail "doctor does not flag old folder"
echo 'state folder migration: PASS'
