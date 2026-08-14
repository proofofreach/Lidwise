#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-agents.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
export VIBECAF_AGENT_PROCESS_FILE="$TEST_ROOT/processes.txt"
export VIBECAF_CLAUDE_SESSIONS="$TEST_ROOT/claude"
export VIBECAF_CODEX_SESSIONS="$TEST_ROOT/codex"
export VIBECAF_AGENT_ACTIVE_WITHIN=90
export VIBECAF_AGENT_RECENT_WITHIN=21600

mkdir -p "$VIBECAF_RUNTIME_DIR" \
  "$VIBECAF_CLAUDE_SESSIONS/project-one" \
  "$VIBECAF_CLAUDE_SESSIONS/project-two" \
  "$VIBECAF_CODEX_SESSIONS/2026/08/14"

cat > "$VIBECAF_AGENT_PROCESS_FILE" <<'PROCESSES'
101 1 /opt/homebrew/bin/claude
102 1 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://
PROCESSES

printf '%s\n' '{"type":"assistant"}' \
  > "$VIBECAF_CLAUDE_SESSIONS/project-one/session-one.jsonl"
printf '%s\n' '{"type":"assistant"}' \
  > "$VIBECAF_CLAUDE_SESSIONS/project-two/session-two.jsonl"
printf '%s\n' '{"type":"assistant"}' \
  > "$VIBECAF_CLAUDE_SESSIONS/project-two/"$'invalid\tsession'".jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"agent_reasoning"}}' \
  > "$VIBECAF_CODEX_SESSIONS/2026/08/14/active.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' \
  > "$VIBECAF_CODEX_SESSIONS/2026/08/14/restartable.jsonl"

# One connected Claude session has gone quiet; the other files are current.
touch -A -000500 "$VIBECAF_CLAUDE_SESSIONS/project-two/session-two.jsonl"

VIBECAF="$ROOT/bin/vibecaf"
"$VIBECAF" agents --refresh >/dev/null

summary=$("$VIBECAF" agents --summary)
grep -q '^Claude Code: 1 active · 1 idle · 0 completed$' <<< "$summary"
grep -q '^Codex: 1 active · 0 idle · 1 completed$' <<< "$summary"
grep -q '^All agents: 2 active · 1 idle · 1 completed$' <<< "$summary"
! "$VIBECAF" agents | grep -q 'invalid'
[ ! -e "$VIBECAF_STATE_DIR/session/active" ]
[ ! -e "$VIBECAF_NOTIFY_LOG" ]

# Per-session freshness, not a provider-global process flag, drives state.
printf '%s\n' \
  '102 1 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://' \
  > "$VIBECAF_AGENT_PROCESS_FILE"
summary=$("$VIBECAF" agents --summary)
grep -q '^Claude Code: 1 active · 1 idle · 0 completed$' <<< "$summary"

# Simulate an already-running manual window. Agent transitions must preserve it.
mkdir -p "$VIBECAF_STATE_DIR/session"
printf '%s\n' active > "$VIBECAF_STATE_DIR/session/active"

# A new turn after completion is a restart, not ownership of the awake window.
printf '%s\n' '{"type":"event_msg","payload":{"type":"user_message"}}' \
  >> "$VIBECAF_CODEX_SESSIONS/2026/08/14/restartable.jsonl"
summary=$("$VIBECAF" agents --summary)
grep -q $'Agent active\tCodex session restarted' "$VIBECAF_NOTIFY_LOG"
grep -q '^Codex: 2 active · 0 idle · 0 completed$' <<< "$summary"
[ -e "$VIBECAF_STATE_DIR/session/active" ]

printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' \
  >> "$VIBECAF_CODEX_SESSIONS/2026/08/14/restartable.jsonl"
"$VIBECAF" agents --refresh >/dev/null
grep -q $'Agent completed\tCodex session completed' "$VIBECAF_NOTIFY_LOG"
[ -e "$VIBECAF_STATE_DIR/session/active" ]

# The normal status path must include the fleet without changing ownership.
cat > "$TEST_ROOT/pmset" <<'PMSET'
#!/bin/bash
case "$*" in
  "-g batt") printf "Now drawing from 'AC Power'\n -InternalBattery-0 100%%; charged\n" ;;
  "-g") printf 'System-wide power settings:\n SleepDisabled 1\n' ;;
esac
PMSET
chmod 0755 "$TEST_ROOT/pmset"
status=$(VIBECAF_PMSET="$TEST_ROOT/pmset" "$VIBECAF" status)
grep -q '^AWAKE MODE: ON$' <<< "$status"
grep -q '^Claude Code:' <<< "$status"
[ -e "$VIBECAF_STATE_DIR/session/active" ]

# A missing scanner clears stale data and degrades without a shell error.
mkdir -p "$TEST_ROOT/empty-run"
mkdir -m 700 "$TEST_ROOT/empty-run/vibecaf-agent-state.$(id -u)"
printf '%s\n' $'codex\tstale\tactive\t0' \
  > "$TEST_ROOT/empty-run/vibecaf-agent-state.$(id -u)/sessions.tsv"
missing=$(VIBECAF_RUNTIME_DIR="$TEST_ROOT/empty-run" \
  VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/missing-scanner" \
  "$VIBECAF" agents --summary 2>&1)
grep -q '^Claude Code: 0 active · 0 idle · 0 completed$' <<< "$missing"
grep -q '^Codex: 0 active · 0 idle · 0 completed$' <<< "$missing"

# A precreated runtime symlink cannot inject a forged cache.
mkdir -p "$TEST_ROOT/symlink-run" "$TEST_ROOT/forged-agent-state"
printf '%s\n' $'codex\tforged\tactive\t0' \
  > "$TEST_ROOT/forged-agent-state/sessions.tsv"
ln -s "$TEST_ROOT/forged-agent-state" \
  "$TEST_ROOT/symlink-run/vibecaf-agent-state.$(id -u)"
forged=$(VIBECAF_RUNTIME_DIR="$TEST_ROOT/symlink-run" \
  VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/missing-scanner" \
  "$VIBECAF" agents --summary 2>&1)
grep -q '^Codex: 0 active · 0 idle · 0 completed$' <<< "$forged"

echo "automatic agent discovery: ok"
