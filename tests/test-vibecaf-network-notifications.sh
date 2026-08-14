#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-network.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_NOTIFY_LOG="$TEST_ROOT/notifications.log"
mkdir -p "$VIBECAF_RUNTIME_DIR"

VIBECAF="$ROOT/bin/vibecaf"

# The first observation establishes a baseline and must not create noise.
"$VIBECAF" __network_transition "" 0
[ ! -e "$VIBECAF_NOTIFY_LOG" ]

"$VIBECAF" __network_transition 0 2
grep -q $'Network disconnected\tNo usable network link' "$VIBECAF_NOTIFY_LOG"

# Repeated observations do not produce repeated alerts.
before=$(wc -l < "$VIBECAF_NOTIFY_LOG")
"$VIBECAF" __network_transition 2 2
[ "$(wc -l < "$VIBECAF_NOTIFY_LOG")" -eq "$before" ]

"$VIBECAF" __network_transition 2 1
grep -q $'Network degraded\tLink is up, but the internet is unreachable' "$VIBECAF_NOTIFY_LOG"

"$VIBECAF" __network_transition 1 0
grep -q $'Network recovered\tInternet access is available again' "$VIBECAF_NOTIFY_LOG"

echo "network notifications: ok"
