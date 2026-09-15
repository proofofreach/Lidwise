#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/.build/helpers/vibecaf-agent-scan-core"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/closedlid-json-events.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
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
echo 'bounded native JSON events and metadata child exclusion: ok'
