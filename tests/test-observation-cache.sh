#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-cache.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
RUNTIME_DIR="$WORK"
AGENT_RUNTIME_DIR="$WORK/runtime"
AGENTSTATEFILE="$AGENT_RUNTIME_DIR/sessions.tsv"
AGENT_CACHE_MAX_AGE=120
source "$ROOT/lib/lidwise/observation.sh"
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
# Both formats share counts, but only the human summary may acquire a cache.
printf 'claude\ta\tworking\t0\ncodex\tb\tfailed\t2\nclaude\tc\twaiting\tbad\n' > "$AGENTSTATEFILE"
result=$(agents_json)
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract claude.working raw -o - -)" = 1 ]
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract codex.failed raw -o - -)" = 1 ]
[ "$(printf '%s' "$result" | /usr/bin/plutil -extract claude.waiting raw -o - -)" = 0 ]
summary=$(agents_summary)
[[ "$summary" == *'All agents: 1 working · 0 waiting · 0 quiet · 0 finished · 1 failed'* ]]
touch -t 200001010000 "$AGENTSTATEFILE"
agents_summary >/dev/null
[ -e "$WORK/scanner-called" ]
echo 'shared counts preserve formatter-specific cache acquisition: ok'


AGENT_NOTIFY=0
OBSERVATION_MAX_TICKS=1
config_notifications() { echo 1; }
goals_refresh() { :; }
agents_refresh() { [ "$AGENT_NOTIFY" = 1 ] || return 1; touch "$WORK/live-setting"; }
observation_refresh_activity() { goals_refresh; agents_refresh; }
observation_loop
[ -f "$WORK/live-setting" ]
echo 'observer reloads live notification preference: ok'

# Exercise scheduling and live network toggles without real time or processes.
(
  clock=0; OBSERVATION_EVERY=60; CHECK_EVERY=20; OBSERVATION_MAX_TICKS=3
  NETSTATEFILE="$WORK/network.state"
  observation_now() { echo "$clock"; }
  sleep() { clock=$((clock + $1)); }
  config_recovery() { if [ "$clock" -ge 20 ] && [ "$clock" -lt 60 ]; then echo 0; else echo 1; fi; }
  network_recovery_enabled() { [ "$NETWORK_RECOVERY" = on ]; }
  network_observe_reset() { :; }
  network_observe_once() { echo "$clock" >> "$WORK/network-ticks"; touch "$NETSTATEFILE"; }
  observation_refresh_activity() { echo "$clock" >> "$WORK/activity-ticks"; }
  observation_loop
  [ "$(tr '\n' ' ' < "$WORK/network-ticks")" = '0 60 80 100 120 ' ]
  [ "$(tr '\n' ' ' < "$WORK/activity-ticks")" = '0 60 120 ' ]
  # Either task can be suppressed independently.
  clock=0; OBSERVATION_MAX_TICKS=1; VIBECAF_NO_OBSERVATION=1
  : > "$WORK/activity-ticks"; : > "$WORK/network-ticks"
  observation_loop
  [ ! -s "$WORK/activity-ticks" ] && [ -s "$WORK/network-ticks" ]
  clock=0; VIBECAF_NO_OBSERVATION=0; VIBECAF_NO_NETWATCH=1
  : > "$WORK/activity-ticks"; : > "$WORK/network-ticks"
  observation_loop
  [ -s "$WORK/activity-ticks" ] && [ ! -s "$WORK/network-ticks" ]
)
echo 'one observer preserves task cadence, live network toggles and independent task flags: ok'
