#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/closedlid-cache.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
RUNTIME_DIR="$WORK"
AGENT_RUNTIME_DIR="$WORK/runtime"
AGENTSTATEFILE="$AGENT_RUNTIME_DIR/sessions.tsv"
AGENT_CACHE_MAX_AGE=120
source "$ROOT/lib/vibecaf/observation.sh"
agents_refresh() { touch "$WORK/scanner-called"; return 1; }
# Missing optional data must never invoke a scanner from the power-status path.
result=$(agents_json)
[ ! -e "$WORK/scanner-called" ]
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract claude.working raw -o - -)" = 0 ]
printf 'claude\tsession\tquiet\t50\n' > "$AGENTSTATEFILE"
result=$(agents_json)
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract claude.quiet raw -o - -)" = 1 ]
touch -t 200001010000 "$AGENTSTATEFILE"
result=$(agents_json)
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract claude.quiet raw -o - -)" = 0 ]
[ ! -e "$WORK/scanner-called" ]
echo 'machine status reads cached observation without scanning: ok'

AGENT_NOTIFY=0
OBSERVATION_MAX_TICKS=1
config_notifications() { echo 1; }
goals_refresh() { :; }
agents_refresh() { [ "$AGENT_NOTIFY" = 1 ] || return 1; touch "$WORK/live-setting"; }
observation_loop
[ -f "$WORK/live-setting" ]
echo 'observer reloads live notification preference: ok'
