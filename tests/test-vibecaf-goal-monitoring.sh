#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-goal-monitor.XXXXXX")
worker_pid=""
cleanup() {
  [ -z "$worker_pid" ] || kill "$worker_pid" 2>/dev/null || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

export HOME="$TEST_ROOT/home"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
mkdir -p "$HOME" "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR"

VIBECAF="$ROOT/bin/vibecaf"

sleep 30 &
worker_pid=$!
"$VIBECAF" goal add "Long build" --pid "$worker_pid"
"$VIBECAF" goals --refresh >/dev/null
grep -q $'Long build\tactive' <("$VIBECAF" goals)

kill "$worker_pid"
wait "$worker_pid" 2>/dev/null || true
worker_pid=""
"$VIBECAF" goals --refresh >/dev/null

grep -q $'Long build\tstopped' <("$VIBECAF" goals)
grep -q $'Goal needs attention\tLong build: process stopped' "$VIBECAF_NOTIFY_LOG"

# A stopped job can be attached to a replacement process without changing the
# global awake window.
sleep 30 &
replacement_pid=$!
"$VIBECAF" goal restart "Long build" --pid "$replacement_pid" >/dev/null
"$VIBECAF" goals --refresh >/dev/null
grep -q $'Long build\tactive' <("$VIBECAF" goals)
[ ! -e "$VIBECAF_STATE_DIR/session/active" ]
kill "$replacement_pid" 2>/dev/null || true
wait "$replacement_pid" 2>/dev/null || true

activity_file="$TEST_ROOT/activity.log"
touch "$activity_file"
"$VIBECAF" goal add "Agent planning" --activity-file "$activity_file" --stale-after 1
sleep 2
"$VIBECAF" goals --refresh >/dev/null
grep -q $'Agent planning\tstalled' <("$VIBECAF" goals)
grep -q $'Goal needs attention\tAgent planning: no activity for' "$VIBECAF_NOTIFY_LOG"

touch "$activity_file"
"$VIBECAF" goals --refresh >/dev/null
grep -q $'Agent planning\tactive' <("$VIBECAF" goals)
grep -q $'Goal active again\tAgent planning' "$VIBECAF_NOTIFY_LOG"

# Observation must not own or end the awake window.
[ ! -e "$VIBECAF_STATE_DIR/session/active" ]

echo "goal process monitoring: ok"
