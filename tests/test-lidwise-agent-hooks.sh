#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-agent-hooks.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SCAN="$ROOT/bin/lidwise-agent-scan"

export VIBECAF_RUNTIME_DIR="$WORK/runtime"
export VIBECAF_AGENT_EVENT_DIR="$WORK/events"
export VIBECAF_CLAUDE_SETTINGS="$WORK/claude-settings.json"
export VIBECAF_CLAUDE_SESSIONS="$WORK/claude-sessions"
export VIBECAF_CODEX_SESSIONS="$WORK/codex-sessions"
export VIBECAF_AGENT_PROCESS_FILE="$WORK/no-processes"
export VIBECAF_AGENT_NOW=10000
export VIBECAF_AGENT_RECENT_WITHIN=600

printf '%s\n' '{"other":{"setting":true},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/keep-me"}]}]}}' > "$VIBECAF_CLAUDE_SETTINGS"

# Preview and status describe support without changing either the settings or
# the power-session runtime state. Codex must remain explicitly unavailable.
before=$(cksum "$VIBECAF_CLAUDE_SETTINGS")
preview=$("$SCAN" --hooks preview claude --json)
grep -q '"old"' <<< "$preview"
grep -q '"new"' <<< "$preview"
status=$("$SCAN" --hooks status --json)
grep -q '"claude":{"supported":true,"configured":false' <<< "$status"
grep -q '"codex":{"supported":false,"configured":false' <<< "$status"
[ "$before" = "$(cksum "$VIBECAF_CLAUDE_SETTINGS")" ]

# Install only adds this product's four Claude hooks. A repeated install is
# idempotent and an explicit remove leaves unrelated hooks and settings intact.
"$SCAN" --hooks install claude >/dev/null
[ "$(plutil -extract other.setting raw "$VIBECAF_CLAUDE_SETTINGS")" = true ]
grep -q '"/keep-me"' "$VIBECAF_CLAUDE_SETTINGS"
[ "$(grep -c -- '--hooks hook claude' "$VIBECAF_CLAUDE_SETTINGS")" = 4 ]
"$SCAN" --hooks install claude >/dev/null
[ "$(grep -c -- '--hooks hook claude' "$VIBECAF_CLAUDE_SETTINGS")" = 4 ]
"$SCAN" --hooks remove claude >/dev/null
[ "$(plutil -extract other.setting raw "$VIBECAF_CLAUDE_SETTINGS")" = true ]
grep -q '"/keep-me"' "$VIBECAF_CLAUDE_SETTINGS"
! grep -q -- '--hooks hook claude' "$VIBECAF_CLAUDE_SETTINGS"
find "$WORK" -name 'claude-settings.json.lidwise-backup.*' -type f | grep -q .

# Removal deletes only Lidwise's command from a mixed hook group.
"$SCAN" --hooks install claude >/dev/null
plutil -insert hooks.Stop.1.hooks.1 -json '{"type":"command","command":"/also-keep-me"}' "$VIBECAF_CLAUDE_SETTINGS"
"$SCAN" --hooks remove all >/dev/null
grep -q '"/also-keep-me"' "$VIBECAF_CLAUDE_SETTINGS"
grep -q '"/keep-me"' "$VIBECAF_CLAUDE_SETTINGS"
! grep -q -- '--hooks hook claude' "$VIBECAF_CLAUDE_SETTINGS"

# Invalid settings and unsafe paths fail closed without changing the target.
printf '%s\n' '{"hooks":{"Stop":"wrong-shape"}}' > "$VIBECAF_CLAUDE_SETTINGS"
bad_before=$(cksum "$VIBECAF_CLAUDE_SETTINGS")
! "$SCAN" --hooks install claude > "$WORK/bad.out" 2>&1
[ "$bad_before" = "$(cksum "$VIBECAF_CLAUDE_SETTINGS")" ]
ln -s "$VIBECAF_CLAUDE_SETTINGS" "$WORK/settings-link.json"
if VIBECAF_CLAUDE_SETTINGS="$WORK/settings-link.json" "$SCAN" --hooks install claude >/dev/null 2>&1; then exit 1; fi
mkdir "$WORK/read-only-settings"
printf '%s\n' '{}' > "$WORK/read-only-settings/settings.json"
chmod 500 "$WORK/read-only-settings"
readonly_before=$(cksum "$WORK/read-only-settings/settings.json")
if VIBECAF_CLAUDE_SETTINGS="$WORK/read-only-settings/settings.json" "$SCAN" --hooks install claude > "$WORK/read-only.out" 2>&1; then exit 1; fi
[ "$readonly_before" = "$(cksum "$WORK/read-only-settings/settings.json")" ]
! grep -q 'hooks installed' "$WORK/read-only.out"
chmod 700 "$WORK/read-only-settings"

# Explicit bounded events are private status metadata. They never rely on a
# transcript, and stale data does not become a current state.
"$SCAN" --hooks event claude working session-a 10000
"$SCAN" --hooks event codex failed session-b 10000
events=$("$SCAN")
grep -q $'^claude\tsession-a\tworking\t0$' <<< "$events"
grep -q $'^codex\tsession-b\tfailed\t0$' <<< "$events"
"$SCAN" --hooks event claude waiting session-stale 9000
! "$SCAN" | grep -q 'session-stale'
! "$SCAN" --hooks event claude finished 'bad session' 10000 >/dev/null 2>&1
[ "$(stat -f %Lp "$VIBECAF_AGENT_EVENT_DIR/events.tsv")" = 600 ]

# Concurrent records survive serialization, and an older event cannot replace
# newer evidence for the same session.
for i in $(seq 1 24); do "$SCAN" --hooks event claude working "race-$i" 10000 & done
wait
[ "$("$SCAN" | grep -c $'^claude\trace-')" = 24 ]
"$SCAN" --hooks event claude failed ordered 10000
"$SCAN" --hooks event claude working ordered 9999
grep -q $'^claude\tordered\tfailed\t0$' < <("$SCAN")

# Private event storage refuses a symlinked directory.
mkdir "$WORK/real-events"
chmod 700 "$WORK/real-events"
ln -s "$WORK/real-events" "$WORK/event-link"
if VIBECAF_AGENT_EVENT_DIR="$WORK/event-link" "$SCAN" --hooks event claude working linked 10000 >/dev/null 2>&1; then exit 1; fi
mkdir "$WORK/redirected-runtime"
chmod 700 "$WORK/redirected-runtime"
ln -s "$WORK/redirected-runtime" "$WORK/runtime-link"
if VIBECAF_AGENT_EVENT_DIR="$WORK/runtime-link/events" "$SCAN" --hooks event claude working linked-parent 10000 >/dev/null 2>&1; then exit 1; fi

# A documented notification maps to waiting. Stop with pending background work
# stays unknown; only a Stop without pending work is an explicit finished turn.
printf '%s' '{"session_id":"session-c","hook_event_name":"Notification","notification_type":"permission_prompt"}' | "$SCAN" --hooks hook claude notification
printf '%s' '{"session_id":"session-d","hook_event_name":"Stop","background_tasks":[{"id":"work"}]}' | "$SCAN" --hooks hook claude stop
printf '%s' '{"session_id":"session-e","hook_event_name":"Stop","background_tasks":[],"session_crons":[]}' | "$SCAN" --hooks hook claude stop
printf '%s' '{"session_id":"session-malformed","hook_event_name":"Stop","background_tasks":"running"}' | "$SCAN" --hooks hook claude stop
printf '%s' '{"session_id":"session-missing","hook_event_name":"Stop"}' | "$SCAN" --hooks hook claude stop
set +o pipefail
{ printf '%s' '{"session_id":"oversized","hook_event_name":"Stop","padding":"'; dd if=/dev/zero bs=70000 count=1 2>/dev/null | tr '\0' x; printf '%s' '"}'; } | "$SCAN" --hooks hook claude stop
set -o pipefail
events=$("$SCAN")
grep -q $'^claude\tsession-c\twaiting\t0$' <<< "$events"
! grep -q $'^claude\tsession-d\t' <<< "$events"
grep -q $'^claude\tsession-e\tfinished\t0$' <<< "$events"
! grep -q 'session-malformed' <<< "$events"
! grep -q 'session-missing' <<< "$events"
! grep -q 'oversized' <<< "$events"

# Hook callbacks fail open. Bad JSON and unavailable event storage cannot
# reject a prompt or force a Stop continuation.
printf '%s' '{bad json' | "$SCAN" --hooks hook claude user-prompt
printf '%s' '{bad json' | VIBECAF_AGENT_EVENT_MAX=invalid "$SCAN" --hooks hook claude user-prompt
mkdir "$WORK/unwritable-runtime"
chmod 500 "$WORK/unwritable-runtime"
printf '%s' '{"session_id":"fail-open","hook_event_name":"UserPromptSubmit"}' \
  | VIBECAF_AGENT_EVENT_DIR="$WORK/unwritable-runtime/events" "$SCAN" --hooks hook claude user-prompt
chmod 700 "$WORK/unwritable-runtime"
! "$SCAN" | grep -q 'fail-open'

# A metadata-only append does not clear a fresh waiting event. A later
# meaningful transcript event does.
mkdir -p "$VIBECAF_CLAUDE_SESSIONS/project"
printf '%s\n' '{"timestamp":"1970-01-01T02:46:39Z","type":"user"}' > "$VIBECAF_CLAUDE_SESSIONS/project/timed.jsonl"
"$SCAN" --hooks event claude waiting timed 10000
printf '%s\n' '{"timestamp":"1970-01-01T02:46:41Z","type":"system"}' >> "$VIBECAF_CLAUDE_SESSIONS/project/timed.jsonl"
grep -q $'^claude\tproject/timed\twaiting\t0$' < <("$SCAN")
printf '%s\n' '{"timestamp":"1970-01-01T02:46:41Z","type":"assistant"}' >> "$VIBECAF_CLAUDE_SESSIONS/project/timed.jsonl"
grep -q $'^claude\tproject/timed\tworking\t0$' < <("$SCAN")
printf '%s\n' '{"timestamp":"1970-01-01T02:46:40.250Z","type":"assistant"}' > "$VIBECAF_CLAUDE_SESSIONS/project/fractional.jsonl"
"$SCAN" --hooks event claude waiting fractional 10000
grep -q $'^claude\tproject/fractional\twaiting\t0$' < <("$SCAN")
printf '%s\n' '{"timestamp":"1970-01-01T02:46:41.250Z","type":"assistant"}' >> "$VIBECAF_CLAUDE_SESSIONS/project/fractional.jsonl"
grep -q $'^claude\tproject/fractional\tworking\t0$' < <("$SCAN")

# A matching transcript outside the bounded selected tail does not suppress
# an explicit event, and a connected fallback does not duplicate it.
printf '%s\n' '{"timestamp":"1970-01-01T02:46:41Z","type":"assistant"}' > "$VIBECAF_CLAUDE_SESSIONS/project/z-selected.jsonl"
"$SCAN" --hooks event claude failed timed 10000
VIBECAF_AGENT_SCAN_MAX=1 "$SCAN" | grep -q $'^claude\ttimed\tfailed\t0$'
printf '%s\n' '123 1 codex' > "$WORK/codex-process"
VIBECAF_AGENT_EVENT_DIR="$WORK/fallback-events" VIBECAF_AGENT_PROCESS_FILE="$WORK/codex-process" \
  "$SCAN" --hooks event codex failed explicit-codex 10000
fallback=$(VIBECAF_AGENT_EVENT_DIR="$WORK/fallback-events" VIBECAF_AGENT_PROCESS_FILE="$WORK/codex-process" \
  VIBECAF_CLAUDE_SESSIONS="$WORK/empty-claude" VIBECAF_CODEX_SESSIONS="$WORK/empty-codex" "$SCAN")
[ "$(grep -c '^codex' <<< "$fallback")" = 1 ]
grep -q $'^codex\texplicit-codex\tfailed\t0$' <<< "$fallback"

# The observer keeps every legacy count and adds explicit attention/failure
# counts; machine JSON remains a cached read and never starts a session.
AGENT_RUNTIME_DIR="$WORK/cache"
AGENTSTATEFILE="$AGENT_RUNTIME_DIR/sessions.tsv"
AGENT_CACHE_MAX_AGE=120
RUNTIME_DIR="$VIBECAF_RUNTIME_DIR"
source "$ROOT/lib/lidwise/observation.sh"
mkdir -p "$AGENT_RUNTIME_DIR"
printf '%s\n' \
  $'claude\twork\tworking\t0' $'claude\twait\twaiting\t0' \
  $'claude\tdone\tfinished\t0' $'claude\tfail\tfailed\t0' \
  $'codex\tquiet\tquiet\t0' > "$AGENTSTATEFILE"
chmod 600 "$AGENTSTATEFILE"
counts=$(agents_json)
[ "$counts" = '{"claude":{"working":1,"waiting":1,"quiet":0,"finished":1,"failed":1},"codex":{"working":0,"waiting":0,"quiet":1,"finished":0,"failed":0}}' ]

echo 'explicit lifecycle events and reversible Claude hooks: ok'
