#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-goals.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
mkdir -p "$HOME" "$VIBECAF_RUNTIME_DIR" "$VIBECAF_STATE_DIR"

VIBECAF="$ROOT/bin/vibecaf"

if "$VIBECAF" goal add "Invalid PID" --pid 0 >/dev/null 2>&1; then
  echo "PID 0 must be rejected" >&2
  exit 1
fi

"$VIBECAF" goal add "API refactor"
"$VIBECAF" goal add "Docs review"

goals=$("$VIBECAF" goals)
grep -q $'API refactor\tactive' <<< "$goals"
grep -q $'Docs review\tactive' <<< "$goals"

"$VIBECAF" goal complete "API refactor" "merged cleanly"
"$VIBECAF" goal fail "Docs review" "agent lost context"

goals=$("$VIBECAF" goals)
grep -q $'API refactor\tcompleted\tmerged cleanly' <<< "$goals"
grep -q $'Docs review\tfailed\tagent lost context' <<< "$goals"
grep -q $'Goal completed\tAPI refactor: merged cleanly' "$VIBECAF_NOTIFY_LOG"
grep -q $'Goal failed\tDocs review: agent lost context' "$VIBECAF_NOTIFY_LOG"

summary=$("$VIBECAF" goals --summary)
[ "$summary" = "0 active · 0 stalled · 1 completed · 1 failed" ]

# Goal state is observational. No goal transition may enable or disable sleep.
[ ! -e "$VIBECAF_STATE_DIR/session/active" ]

echo "goal lifecycle: ok"
