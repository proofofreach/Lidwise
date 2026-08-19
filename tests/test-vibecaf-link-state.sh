#!/bin/bash
# The classifier is the piece that decides which recovery rung to use, so every
# state it can return is pinned here with stubbed system tools.
#
# The bug this exists to prevent: the old net_state returned a single "no usable
# link" code for both "joined, lease expired" and "joined to nothing". The
# watchdog answered both by cutting the radio, which on 2026-08-19 turned a
# recoverable lease expiry into a 4m47s outage.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/vibecaf-linkstate.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

BIN="$TEST_ROOT/bin"; mkdir -p "$BIN"
export VIBECAF_STATE_DIR="$TEST_ROOT/state"
export VIBECAF_RUNTIME_DIR="$TEST_ROOT/run"
mkdir -p "$VIBECAF_RUNTIME_DIR"

export VIBECAF_NETWORKSETUP="$BIN/networksetup"
export VIBECAF_IPCONFIG="$BIN/ipconfig"
export VIBECAF_ROUTE="$BIN/route"
export VIBECAF_CURL="$BIN/curl"

# Stubs read their answers out of the environment so each case is one export.
cat > "$BIN/networksetup" <<'EOF'
#!/bin/bash
case "${1:-}" in
  -listallhardwareports) printf 'Hardware Port: Wi-Fi\nDevice: en0\n' ;;
  -getairportpower)      echo "Wi-Fi Power (en0): ${STUB_RADIO:-On}" ;;
  -listnetworkserviceorder)
    [ "${STUB_SVC:-yes}" = yes ] && printf '(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)\n\n' ;;
  -setdhcp) [ -n "${STUB_CALLS:-}" ] && echo "$*" >> "$STUB_CALLS" ;;
esac
exit 0
EOF
cat > "$BIN/ipconfig" <<'EOF'
#!/bin/bash
case "${1:-}" in
  getsummary) [ "${STUB_ASSOC:-yes}" = yes ] && printf '  SSID : <redacted>\n' ;;
  getifaddr)  [ -n "${STUB_IP:-}" ] && echo "$STUB_IP" || exit 1 ;;
esac
exit 0
EOF
cat > "$BIN/route" <<'EOF'
#!/bin/bash
[ -z "${STUB_GW:-}" ] && exit 1
echo "  gateway: $STUB_GW"
echo "  interface: ${STUB_RIF:-en0}"
EOF
cat > "$BIN/curl" <<'EOF'
#!/bin/bash
# Mimic `curl -s -o <file> -w '%{http_code}'`: body to the -o target, code to stdout.
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf '%s' "${STUB_BODY:-}" > "$out"
printf '%s' "${STUB_CODE:-000}"
EOF
chmod +x "$BIN"/*

probe() { "$ROOT/bin/vibecaf" netdiag 2>/dev/null | awk '/^state:/{print $2}'; }

expect() {  # expect <want> <label>
  local got; got=$(probe)
  if [ "$got" != "$1" ]; then echo "FAIL: $2 — wanted $1, got $got" >&2; exit 1; fi
  echo "  ok: $2 -> $1"
}

export STUB_RIF=en0

echo "link_state:"

STUB_RADIO=Off STUB_ASSOC=yes STUB_IP=10.0.0.5 STUB_GW=10.0.0.1 \
  expect radio_off "radio powered down"

STUB_RADIO=On STUB_ASSOC=no STUB_IP= STUB_GW= \
  expect unassoc "powered but joined to nothing"

# The 2026-08-19 failure: still associated, lease and route gone.
STUB_RADIO=On STUB_ASSOC=yes STUB_IP= STUB_GW= \
  expect noip "associated, no address"

STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.5 STUB_GW= \
  expect noip "associated with an address but no default route"

STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.5 STUB_GW=10.0.0.1 \
  STUB_CODE=200 STUB_BODY='<html>Success</html>' \
  expect online "probe returns Success"

STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.5 STUB_GW=10.0.0.1 \
  STUB_CODE=200 STUB_BODY='<html>Please sign in</html>' \
  expect portal "something answers HTTP but it is not the internet"

STUB_RADIO=On STUB_ASSOC=yes STUB_IP=10.0.0.5 STUB_GW=10.0.0.1 \
  STUB_CODE=000 STUB_BODY='' \
  expect deadlink "route exists, nothing answers"

# A tethered iPhone or USB ethernet carrying the route means the Wi-Fi link
# layer is not the question — go straight to the probe.
STUB_RADIO=Off STUB_ASSOC=no STUB_IP= STUB_GW=192.168.2.1 STUB_RIF=en9 \
  STUB_CODE=200 STUB_BODY='Success' \
  expect online "another interface carries the default route"

echo "dhcp renew:"
# The renew must run at the service layer — networksetup writes to the Wi-Fi
# *service* — never `ipconfig set <dev> DHCP`, whose interface-layer override
# displaces the real service as primary and wedges the macOS reachability UI
# ("No Internet Connection" while traffic flows). Found live on 2026-08-19.
CALLS="$TEST_ROOT/setdhcp.calls"
if STUB_IP=10.0.0.5 STUB_CALLS="$CALLS" "$ROOT/bin/vibecaf" __dhcp_renew en0; then
  echo "  ok: renew succeeds once the device has an address"
else
  echo "FAIL: renew reported failure on the success path" >&2; exit 1
fi
if [ "$(cat "$CALLS")" = "-setdhcp Wi-Fi vibecaf-renew
-setdhcp Wi-Fi" ]; then
  echo "  ok: exactly two service-layer writes — set client-id, clear client-id"
else
  echo "FAIL: unexpected networksetup calls:" >&2; cat "$CALLS" >&2; exit 1
fi
: > "$CALLS"
if STUB_SVC=no STUB_IP=10.0.0.5 STUB_CALLS="$CALLS" "$ROOT/bin/vibecaf" __dhcp_renew en0; then
  echo "FAIL: renew claimed success with no network service mapped" >&2; exit 1
elif [ -s "$CALLS" ]; then
  echo "FAIL: renew touched the service config despite resolving none" >&2; exit 1
else
  echo "  ok: no service mapped -> fails cleanly, writes nothing"
fi
case "$("$ROOT/bin/vibecaf" netdiag 2>/dev/null | grep '^DHCP renew:')" in
  *"available (service: Wi-Fi)"*) echo "  ok: netdiag reports the resolved service" ;;
  *) echo "FAIL: netdiag DHCP renew line wrong" >&2; exit 1 ;;
esac

echo "carrier:"
carrier() { "$ROOT/bin/vibecaf" netdiag 2>/dev/null | awk -F': +' '/^carrier:/{print $2}'; }

out=$(STUB_RADIO=On STUB_ASSOC=yes STUB_IP=172.20.10.4 STUB_GW=172.20.10.1 \
      STUB_CODE=200 STUB_BODY=Success carrier)
case "$out" in *"Personal Hotspot"*) echo "  ok: 172.20.10.x reads as the iPhone hotspot" ;;
  *) echo "FAIL: hotspot subnet not detected — got '$out'" >&2; exit 1 ;; esac

out=$(STUB_RADIO=On STUB_ASSOC=yes STUB_IP=192.168.0.9 STUB_GW=192.168.0.1 \
      STUB_CODE=200 STUB_BODY=Success carrier)
case "$out" in "Wi-Fi") echo "  ok: an ordinary subnet reads as Wi-Fi" ;;
  *) echo "FAIL: wanted Wi-Fi — got '$out'" >&2; exit 1 ;; esac

echo "link state: ok"
