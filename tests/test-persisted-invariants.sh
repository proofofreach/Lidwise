#!/bin/bash
# Regressions for invariants at module boundaries and in persisted data that
# were relied on but not enforced (goals, agent records, agent scan bounds).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-invariants.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd "$WORK" && pwd)
export VIBECAF_RUNTIME_DIR="$WORK/run" VIBECAF_STATE_DIR="$WORK/state" VIBECAF_NOTIFY_LOG="$WORK/notify"
export VIBECAF_NO_NETWATCH=1
mkdir -p "$WORK/run" "$WORK/state" "$WORK/cwd"; : > "$VIBECAF_NOTIFY_LOG"
L="$ROOT/bin/lidwise"
fail() { echo "FAIL: $*" >&2; exit 1; }
goal_field() { cat "$VIBECAF_STATE_DIR/goals/$(printf '%s' "$1" | shasum -a 256 | cut -c1-16)/$2"; }

# A relative activity file is stored absolute, so the observer (another cwd)
# sees the same file; a missing one is rejected instead of silently stalling.
touch "$WORK/cwd/progress.log"
(cd "$WORK/cwd" && "$L" goal add build --activity-file progress.log --stale-after 60 >/dev/null)
[ "$(goal_field build activity_file)" = "$WORK/cwd/progress.log" ] || fail "activity file stored relative"
(cd / && "$L" goals --refresh >/dev/null)
[ "$(goal_field build observed)" = active ] || fail "goal stalled when refreshed from another cwd"
! "$L" goal add other --activity-file "$WORK/missing.log" >/dev/null 2>&1 || fail "missing activity file accepted"

# Restart keeps monitoring options that are not overridden.
"$L" goal restart build >/dev/null
[ "$(goal_field build stale_after)" = 60 ] && [ "$(goal_field build activity_file)" = "$WORK/cwd/progress.log" ] ||
  fail "restart dropped monitoring options"

# A live process owned by another user (kill -0 fails with EPERM) is alive.
"$L" goal add rootwork --pid 1 >/dev/null
"$L" goals --refresh >/dev/null
[ "$(goal_field rootwork observed)" = active ] || fail "pid 1 reported stopped"

# Messages and bounds that would not read back are rejected.
! "$L" goal touch build $'a\nb' >/dev/null 2>&1 || fail "multi-line message accepted"
! "$L" goal add big --stale-after 99999999999999999999 >/dev/null 2>&1 || fail "unreadable stale-after accepted"

# Legacy agent records (no updated_at) expire by age, freeing the record cap.
mkdir -p -m 700 "$VIBECAF_STATE_DIR/agents/legacy0000000000"
printf 'completed\n' > "$VIBECAF_STATE_DIR/agents/legacy0000000000/state"
touch -t 202001010000 "$VIBECAF_STATE_DIR/agents/legacy0000000000"
printf '#!/bin/bash\nprintf "claude\\tmain\\tworking\\t1\\n"\n' > "$WORK/scan"; chmod 755 "$WORK/scan"
VIBECAF_AGENT_SCAN_CMD="$WORK/scan" "$L" __observation_scan >/dev/null
[ ! -e "$VIBECAF_STATE_DIR/agents/legacy0000000000" ] || fail "legacy agent record never pruned"
! ls "$VIBECAF_RUNTIME_DIR/agent-state/sessions.tsv."* >/dev/null 2>&1 || fail "agent snapshot temp file leaked"
grep -q $'claude\tmain\tworking' "$VIBECAF_RUNTIME_DIR/agent-state/sessions.tsv"

# Many recent subagent transcripts do not evict the main session from the
# bounded scan.
export VIBECAF_CLAUDE_SESSIONS="$WORK/claude" VIBECAF_CODEX_SESSIONS="$WORK/codex" VIBECAF_AGENT_SCAN_MAX=5
export VIBECAF_AGENT_EVENT_DIR="$WORK/events" VIBECAF_CLAUDE_SETTINGS="$WORK/none.json" VIBECAF_AGENT_PROCESS_FILE="$WORK/none"
mkdir -p "$WORK/claude/proj/main-session/subagents" "$WORK/codex"
printf '{}\n' > "$WORK/claude/proj/main-session.jsonl"
for i in 1 2 3 4 5 6 7 8; do printf '{}\n' > "$WORK/claude/proj/main-session/subagents/agent-$i.jsonl"; done
"$ROOT/bin/lidwise-agent-scan" | grep -q $'claude\tproj/main-session\t' || fail "subagent files evicted the main session"

echo 'persisted invariants: PASS'
