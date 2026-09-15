#!/bin/bash
# Exercise the recovery loop itself with system calls stubbed. These cases pin
# both the chosen interface and the prohibited configuration writes.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-network-loop.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
BIN="$TEST_ROOT/bin"; mkdir -p "$BIN" "$TEST_ROOT/run"
export VIBECAF_NETLOG="$TEST_ROOT/logs/network.log"
export VIBECAF_AGENT_SCAN_CMD="$TEST_ROOT/no-scanner"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_NETWORKSETUP="$BIN/networksetup"
export VIBECAF_IPCONFIG="$BIN/ipconfig"
export VIBECAF_ROUTE="$BIN/route"
export VIBECAF_CURL="$BIN/curl"
export VIBECAF_NETWATCH_MAX_TICKS=1
export VIBECAF_NETWATCH_NO_SLEEP=1
export PATH="$BIN:$PATH"

cat > "$BIN/networksetup" <<'EOF'
#!/bin/bash
case "$1" in
  -listallhardwareports) printf 'Hardware Port: Wi-Fi\nDevice: en0\n' ;;
  -listnetworkserviceorder) printf '(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)\n' ;;
  -getairportpower) echo "Wi-Fi Power (en0): ${STUB_RADIO:-On}" ;;
  -getinfo) case "${STUB_METHOD:-dhcp}" in dhcp) printf 'DHCP Configuration\nClient ID: preserved-id\n' ;; static) printf 'Manual Configuration\n' ;; esac ;;
  -renewdhcp|-setdhcp|-setairportpower) printf '%s\n' "$*" >> "$STUB_CALLS" ;;
esac
EOF
cat > "$BIN/ipconfig" <<'EOF'
#!/bin/bash
case "$1" in
  getsummary) [ "${STUB_ASSOC:-yes}" = yes ] && printf ' SSID : <redacted>\n' ;;
  getifaddr) [ -n "${STUB_IP:-}" ] && printf '%s\n' "$STUB_IP" || exit 1 ;;
esac
EOF
cat > "$BIN/route" <<'EOF'
#!/bin/bash
[ -n "${STUB_GW:-}" ] && printf ' gateway: %s\n' "$STUB_GW"
[ -n "${STUB_RIF:-}" ] && printf ' interface: %s\n' "$STUB_RIF"
EOF
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
out= prev=
for arg in "$@"; do [ "$prev" = -o ] && out=$arg; prev=$arg; done
[ -z "$out" ] || printf '%s' "${STUB_BODY:-}" > "$out"
printf '%s' "${STUB_CODE:-000}"
EOF
cat > "$BIN/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$BIN/pmset" <<'EOF'
#!/bin/bash
case "$*" in
  "-g batt") printf "Now drawing from 'AC Power'\n -InternalBattery-0 100%%; charged\n" ;;
  "-g") printf 'System-wide power settings:\n SleepDisabled 0\n' ;;
esac
EOF
chmod 0755 "$BIN"/*
export VIBECAF_PMSET="$BIN/pmset"

run_loop() {
  : > "$STUB_CALLS"
  "$ROOT/bin/vibecaf" __netwatch >/dev/null
}
assert_no_write() {
  [ ! -s "$STUB_CALLS" ] || { echo "unexpected network write for $1:" >&2; cat "$STUB_CALLS" >&2; exit 1; }
}

export STUB_CALLS="$TEST_ROOT/calls"

# An associated Wi-Fi interface with no lease is diagnosed but never mutated.
# Its DHCP client ID and service settings must remain untouched.
STUB_RADIO=On STUB_ASSOC=yes STUB_IP= STUB_RIF=en0 STUB_GW= STUB_METHOD=dhcp run_loop
assert_no_write 'missing DHCP lease'

# Static IPv4 uses the same diagnosis but stays entirely read-only.
STUB_RADIO=On STUB_ASSOC=yes STUB_IP= STUB_RIF=en0 STUB_GW= STUB_METHOD=static run_loop
assert_no_write 'static IPv4'

# A captive portal and an upstream failure are passive. They must never reset
# Wi-Fi, even though Wi-Fi is the default route.
STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.4 STUB_RIF=en0 STUB_GW=10.0.0.1 STUB_CODE=200 STUB_BODY='sign in' run_loop
assert_no_write 'captive portal'
STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.4 STUB_RIF=en0 STUB_GW=10.0.0.1 STUB_CODE=000 STUB_BODY= run_loop
assert_no_write 'upstream failure'

# Ethernet/VPN paths are observed through the probe but never cause a Wi-Fi
# action. Wi-Fi radio-off is also treated as deliberate and stays untouched.
STUB_RADIO=Off STUB_ASSOC=no STUB_IP= STUB_RIF=en9 STUB_GW=192.168.2.1 STUB_CODE=000 STUB_BODY= run_loop
assert_no_write 'Ethernet/VPN upstream failure'
STUB_RADIO=Off STUB_ASSOC=no STUB_IP= STUB_RIF= STUB_GW= STUB_CODE=000 STUB_BODY= run_loop
assert_no_write 'manual Wi-Fi off'

# An unassociated Wi-Fi interface is also diagnostic only. The monitor does
# not force auto-join because that changes the radio state behind the user.
STUB_RADIO=On STUB_ASSOC=no STUB_IP= STUB_RIF= STUB_GW= STUB_CODE=000 STUB_BODY= run_loop
assert_no_write 'unassociated Wi-Fi'

# The live recovery setting is visible to the loop: off turns every state into
# observation-only behavior.
NETWORK_RECOVERY=off STUB_RADIO=On STUB_ASSOC=no STUB_IP= STUB_RIF= STUB_GW= STUB_CODE=000 STUB_BODY= run_loop
assert_no_write 'recovery disabled'

# Cache data is untrusted runtime input. A bad timestamp, stale timestamp, or
# invented token must degrade to unknown instead of feeding shell arithmetic or
# presenting an old verdict as live.
printf 'not-a-time\tportal\n' > "$VIBECAF_RUNTIME_DIR/network.state"
grep -q '^Network: unknown$' <("$ROOT/bin/vibecaf" status)
printf '1\tinvented-state\n' > "$VIBECAF_RUNTIME_DIR/network.state"
grep -q '^Network: unknown$' <("$ROOT/bin/vibecaf" status)

# wc output is padded on macOS. Trimming must still enforce the bound.
VIBECAF_NETLOG_MAX_LINES=3 STUB_RADIO=On STUB_ASSOC=no STUB_IP= STUB_RIF= STUB_GW= run_loop
[ "$(wc -l < "$VIBECAF_NETLOG" | tr -d '[:space:]')" -le 3 ]
[ "$(stat -f %Lp "$VIBECAF_NETLOG")" = 600 ]
[ "$(stat -f %Lp "$VIBECAF_RUNTIME_DIR/network.state")" = 600 ]
printf 'preserve\n' > "$TEST_ROOT/sentinel"
rm "$VIBECAF_RUNTIME_DIR/network.state"
ln -s "$TEST_ROOT/sentinel" "$VIBECAF_RUNTIME_DIR/network.state"
STUB_RADIO=On STUB_ASSOC=no STUB_IP= STUB_RIF= STUB_GW= run_loop || true
[ "$(cat "$TEST_ROOT/sentinel")" = preserve ]
echo 'network recovery loop: ok'
