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

# States are named tokens now, not 0/1/2. The rename is the point: the old code
# collapsed "joined but the lease died" and "joined to nothing" into the same
# code 2, and then applied the same radio bounce to both.

# The first observation establishes a baseline and must not create noise.
"$VIBECAF" __network_transition "" online
[ ! -e "$VIBECAF_NOTIFY_LOG" ]

"$VIBECAF" __network_transition online unassoc
grep -q $'Network disconnected\tWi-Fi is not joined to any network' "$VIBECAF_NOTIFY_LOG"

# Repeated observations do not produce repeated alerts.
before=$(wc -l < "$VIBECAF_NOTIFY_LOG")
"$VIBECAF" __network_transition unassoc unassoc
[ "$(wc -l < "$VIBECAF_NOTIFY_LOG")" -eq "$before" ]

"$VIBECAF" __network_transition unassoc deadlink
grep -q $'Network degraded\tLink is up, but the internet is unreachable' "$VIBECAF_NOTIFY_LOG"

# The two states that used to be indistinguishable each get their own alert,
# because they call for opposite responses: renew the lease vs. open a browser.
"$VIBECAF" __network_transition deadlink noip
grep -q $'Lost IP address\tJoined, but the DHCP lease is gone' "$VIBECAF_NOTIFY_LOG"

"$VIBECAF" __network_transition noip portal
grep -q $'Captive portal\tLog in with a browser to get back online' "$VIBECAF_NOTIFY_LOG"

"$VIBECAF" __network_transition portal radio_off
grep -q $'Wi-Fi is off\tThe radio is powered down' "$VIBECAF_NOTIFY_LOG"

"$VIBECAF" __network_transition radio_off online
grep -q $'Network recovered\tInternet access is available again' "$VIBECAF_NOTIFY_LOG"

echo "network notifications: ok"
