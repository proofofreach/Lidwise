#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/.build/helpers/vibecaf-agent-scan-core"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/closedlid-json-events.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
"$HELPER" --run-bounded 1 /bin/sh -c 'printf stdout; printf stderr >&2; exit 7' \
  > "$WORK/bounded.stdout" 2> "$WORK/bounded.stderr" && exit 1
[ "$(cat "$WORK/bounded.stdout")" = stdout ]
[ "$(cat "$WORK/bounded.stderr")" = stderr ]
start=$(date +%s)
"$HELPER" --run-bounded 1 /bin/sh -c 'sleep 60 & echo "$!" > "$1"; exit 0' \
  bounded-test "$WORK/descendant.pid" > /dev/null 2>&1 && exit 1
[ $(( $(date +%s) - start )) -lt 3 ]
descendant=$(cat "$WORK/descendant.pid")
if kill -0 "$descendant" 2>/dev/null; then
  case "$(ps -o stat= -p "$descendant" 2>/dev/null | tr -d '[:space:]')" in Z*) ;; *) exit 1 ;; esac
fi
"$HELPER" --run-bounded 0 /bin/true > /dev/null 2>&1 && exit 1
"$HELPER" --run-bounded 1 bin/true > /dev/null 2>&1 && exit 1
printf '%s\n' '{"type":"session_meta","payload":{"source":{"subagent":{"spawn":{"parent_thread_id":"parent"}}}}}' '{"type":"event_msg","payload":{"type":"task_complete"}}' > "$WORK/child.jsonl"
[ "$("$HELPER" codex "$WORK/child.jsonl")" = child ]
printf '%s\n' '{ "type": "event_msg", "payload": {"type": "task_complete"} }' 'not json' > "$WORK/events.jsonl"
[ "$("$HELPER" codex "$WORK/events.jsonl")" = finished ]
printf '%s\n' '{"type":"event_msg","payload":{"type":"user_message"}}' >> "$WORK/events.jsonl"
[ "$("$HELPER" codex "$WORK/events.jsonl")" = working ]
printf '%s\n' '{"type":"user","message":"result success task_complete"}' > "$WORK/quoted.jsonl"
[ "$("$HELPER" claude "$WORK/quoted.jsonl")" = working ]
printf '%s\n' '{"type":"result","subtype":"error_during_execution"}' > "$WORK/error.jsonl"
[ -z "$("$HELPER" claude "$WORK/error.jsonl")" ]
# Codex Desktop resumes with response_item events after a prior completed turn.
for kind in reasoning function_call custom_tool_call function_call_output custom_tool_call_output; do
  printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' "{\"type\":\"response_item\",\"payload\":{\"type\":\"$kind\"}}" > "$WORK/desktop.jsonl"
  [ "$("$HELPER" codex "$WORK/desktop.jsonl")" = working ]
done
for role in user assistant; do
  printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"$role\"}}" > "$WORK/desktop.jsonl"
  [ "$("$HELPER" codex "$WORK/desktop.jsonl")" = working ]
done
printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete"}}' '{"type":"event_msg","payload":{"type":"token_count"}}' '{"type":"response_item","payload":{"type":"message","role":"system"}}' > "$WORK/desktop.jsonl"
[ "$("$HELPER" codex "$WORK/desktop.jsonl")" = finished ]
printf '%s\n' '{"type":"response_item","payload":{"type":"reasoning"}}' '{"type":"event_msg","payload":{"type":"task_complete"}}' > "$WORK/desktop.jsonl"
[ "$("$HELPER" codex "$WORK/desktop.jsonl")" = finished ]
echo 'bounded runner, native JSON events, Desktop resumed turns and metadata child exclusion: ok'
