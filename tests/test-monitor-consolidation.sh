#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-monitor.XXXXXX")
export VIBECAF_RUNTIME_DIR="$WORK/run" VIBECAF_STATE_DIR="$WORK/state"
export VIBECAF_NETWORKSETUP=/usr/bin/false VIBECAF_OBSERVATION_RUNNER=/usr/bin/true
export VIBECAF_CHECK_EVERY=1 VIBECAF_OBSERVATION_EVERY=1
export VIBECAF_PMSET="$WORK/pmset"
cat > "$VIBECAF_PMSET" <<'EOF'
#!/bin/bash
[ "$*" = -g ] || exit 1
printf ' SleepDisabled 1\n'
EOF
chmod 700 "$VIBECAF_PMSET"
# Load the actual lifecycle functions, without executing a user command.
sed '/^command=${1:-toggle}/,$d' "$ROOT/bin/lidwise" > "$WORK/functions.sh"
source "$WORK/functions.sh"
SELF="$ROOT/bin/lidwise"
cleanup() {
  stop_observation "${session_id:-}" || true
  process_record_signal "$NETPIDFILE" netwatch "${session_id:-}" || true
  rm -rf "$WORK"
}
trap cleanup EXIT
session_id="$(date +%s).$$.1"
session_claim "$session_id" "$(date +%s)" 300
session_activate
start_network_monitor
first=$(observation_pid "$session_id")
[ ! -e "$NETPIDFILE" ]
start_network_monitor
[ "$(observation_pid "$session_id")" = "$first" ]
config_set_locked recovery off >/dev/null
[ "$(observation_pid "$session_id")" = "$first" ]
[ ! -e "$NETSTATEFILE" ]
config_set_locked recovery on >/dev/null
[ "$(observation_pid "$session_id")" = "$first" ]
for n in {1..40}; do [ ! -f "$NETSTATEFILE" ] || break; sleep 0.1; done
[ -f "$NETSTATEFILE" ]
# A verified older netwatch is still retired during an upgrade/restart.
start_owned_process netwatch "$NETPIDFILE" "$SELF" __netwatch
legacy=$(netwatch_pid "$session_id")
start_network_monitor
! process_start_identity "$legacy" | grep -q .
[ "$(observation_pid "$session_id")" = "$first" ]
retire_session_processes "$session_id"
! observation_pid "$session_id" >/dev/null
[ ! -e "$NETPIDFILE" ] && [ ! -e "$OBSPIDFILE" ]
export VIBECAF_NO_OBSERVATION=1
config_set_locked recovery off >/dev/null
start_observation
! observation_pid "$session_id" >/dev/null
config_set_locked recovery on >/dev/null
observation_pid "$session_id" >/dev/null
config_set_locked recovery off >/dev/null
! observation_pid "$session_id" >/dev/null
echo 'one optional worker, independent network toggle, duplicate prevention and legacy cleanup: ok'
