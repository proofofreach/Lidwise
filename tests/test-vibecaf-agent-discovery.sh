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
# Transition notifications are opt-in; this test asserts on them.
export VIBECAF_AGENT_NOTIFY=1

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

# Completion comes only from valid structured lifecycle records. Silence stays
# quiet, malformed JSON does not become a false finish, and child traces do not
# create independent sessions.
mkdir -p "$TEST_ROOT/scanner-edge/codex/subagents" "$TEST_ROOT/scanner-edge/claude"
printf '%s\n' '{ "type" : "event_msg", "payload" : { "type" : "task_complete" } }' \
  > "$TEST_ROOT/scanner-edge/codex/spaced.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}' \
  > "$TEST_ROOT/scanner-edge/codex/malformed.jsonl"
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' \
  > "$TEST_ROOT/scanner-edge/codex/subagents/child.jsonl"
printf '%s\n' '{"type":"assistant"}' > "$TEST_ROOT/scanner-edge/codex/quiet.jsonl"
printf '%s\n' '{ "type" : "result", "subtype" : "success" }' \
  > "$TEST_ROOT/scanner-edge/claude/finished.jsonl"
touch -A -000601 "$TEST_ROOT/scanner-edge/codex/quiet.jsonl"
edge=$(VIBECAF_CODEX_SESSIONS="$TEST_ROOT/scanner-edge/codex" \
  VIBECAF_CLAUDE_SESSIONS="$TEST_ROOT/scanner-edge/claude" \
  VIBECAF_AGENT_RECENT_WITHIN=21600 VIBECAF_AGENT_PROCESS_FILE="$TEST_ROOT/missing-processes" \
  "$ROOT/bin/vibecaf-agent-scan")
grep -q $'^codex\tspaced\tfinished\t' <<< "$edge"
grep -q $'^codex\tmalformed\tworking\t' <<< "$edge"
grep -q $'^codex\tquiet\tquiet\t' <<< "$edge"
grep -q $'^claude\tfinished\tfinished\t' <<< "$edge"
! grep -q 'child' <<< "$edge"

"$VIBECAF" agents --refresh >/dev/null

summary=$("$VIBECAF" agents --summary)
grep -q '^Claude Code: 1 working · 1 quiet · 0 finished$' <<< "$summary"
grep -q '^Codex: 1 working · 0 quiet · 1 finished$' <<< "$summary"
grep -q '^All agents: 2 working · 1 quiet · 1 finished$' <<< "$summary"
! "$VIBECAF" agents | grep -q 'invalid'
[ ! -e "$VIBECAF_STATE_DIR/session/active" ]
[ ! -e "$VIBECAF_NOTIFY_LOG" ]

# MCP servers are not sessions: with no Codex logs, `codex mcp-server` alone
# must not produce a synthetic idle Codex row.
mkdir -p "$TEST_ROOT/mcp-only"
printf '%s\n' \
  '201 1 node /opt/homebrew/bin/codex mcp-server' \
  '202 201 /opt/homebrew/lib/node_modules/@openai/codex/vendor/bin/codex mcp-server' \
  '203 1 claude mcp serve' \
  '204 1 /Applications/ChatGPT.app/Contents/Frameworks/Codex Framework.framework/Helpers/browser_crashpad_handler --monitor-self' \
  '206 1 /opt/homebrew/bin/claude --chrome-native-host' \
  > "$TEST_ROOT/mcp-only/processes.txt"
mcp_summary=$(VIBECAF_AGENT_PROCESS_FILE="$TEST_ROOT/mcp-only/processes.txt" \
  VIBECAF_CODEX_SESSIONS="$TEST_ROOT/mcp-only/codex" \
  VIBECAF_CLAUDE_SESSIONS="$TEST_ROOT/mcp-only/claude" \
  "$ROOT/bin/vibecaf-agent-scan")
[ -z "$mcp_summary" ]
# …but a real Codex CLI process still counts as connected.
printf '%s\n' '205 1 /opt/homebrew/bin/codex' > "$TEST_ROOT/mcp-only/processes.txt"
mcp_summary=$(VIBECAF_AGENT_PROCESS_FILE="$TEST_ROOT/mcp-only/processes.txt" \
  VIBECAF_CODEX_SESSIONS="$TEST_ROOT/mcp-only/codex" \
  VIBECAF_CLAUDE_SESSIONS="$TEST_ROOT/mcp-only/claude" \
  "$ROOT/bin/vibecaf-agent-scan")
grep -q $'^codex\tcodex\tquiet\t0$' <<< "$mcp_summary"

# Per-session freshness, not a provider-global process flag, drives state.
printf '%s\n' \
  '102 1 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://' \
  > "$VIBECAF_AGENT_PROCESS_FILE"
summary=$("$VIBECAF" agents --summary)
grep -q '^Claude Code: 1 working · 1 quiet · 0 finished$' <<< "$summary"

# Seed incomplete session residue. Agent transitions must preserve it.
mkdir -p "$VIBECAF_STATE_DIR/session"
printf '%s\n' active > "$VIBECAF_STATE_DIR/session/active"

# A new turn after completion is a restart, not ownership of the awake window.
printf '%s\n' '{"type":"event_msg","payload":{"type":"user_message"}}' \
  >> "$VIBECAF_CODEX_SESSIONS/2026/08/14/restartable.jsonl"
summary=$("$VIBECAF" agents --summary)
grep -q $'Agent working\tCodex session restarted' "$VIBECAF_NOTIFY_LOG"
grep -q '^Codex: 2 working · 0 quiet · 0 finished$' <<< "$summary"
[ -e "$VIBECAF_STATE_DIR/session/active" ]

printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' \
  >> "$VIBECAF_CODEX_SESSIONS/2026/08/14/restartable.jsonl"
"$VIBECAF" agents --refresh >/dev/null
grep -q $'Agent finished\tCodex session reported completion' "$VIBECAF_NOTIFY_LOG"
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
# Incomplete ownership evidence is unknown, never safely external.
grep -q '^AWAKE MODE: UNKNOWN$' <<< "$status"
grep -q '^Claude Code:' <<< "$status"
[ -e "$VIBECAF_STATE_DIR/session/active" ]

# The versioned status contract consumes observer JSON without making observer
# state part of awake-session ownership.
status_json=$(VIBECAF_PMSET="$TEST_ROOT/pmset" "$VIBECAF" status --json)
grep -q '"agents":{"claude":{"working":1,"quiet":1,"finished":0},"codex":{"working":1,"quiet":0,"finished":1}}' <<< "$status_json"
grep -q '"goals":{"active":0,"stalled":0,"completed":0,"failed":0}' <<< "$status_json"

# A missing scanner clears stale data and degrades without a shell error.
mkdir -p "$TEST_ROOT/empty-run"
mkdir -m 700 "$TEST_ROOT/empty-run/agent-state"
printf '%s\n' $'codex\tstale\tactive\t0' \
  > "$TEST_ROOT/empty-run/agent-state/sessions.tsv"
missing=$(VIBECAF_RUNTIME_DIR="$TEST_ROOT/empty-run" \
  VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/missing-scanner" \
  "$VIBECAF" agents --summary 2>&1)
grep -q '^Claude Code: 0 working · 0 quiet · 0 finished$' <<< "$missing"
grep -q '^Codex: 0 working · 0 quiet · 0 finished$' <<< "$missing"

# A precreated runtime symlink cannot inject a forged cache.
mkdir -p "$TEST_ROOT/symlink-run" "$TEST_ROOT/forged-agent-state"
printf '%s\n' $'codex\tforged\tactive\t0' \
  > "$TEST_ROOT/forged-agent-state/sessions.tsv"
ln -s "$TEST_ROOT/forged-agent-state" \
  "$TEST_ROOT/symlink-run/agent-state"
forged=$(VIBECAF_RUNTIME_DIR="$TEST_ROOT/symlink-run" \
  VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/missing-scanner" \
  "$VIBECAF" agents --summary 2>&1)
grep -q '^Codex: 0 working · 0 quiet · 0 finished$' <<< "$forged"

echo "automatic agent discovery: ok"
