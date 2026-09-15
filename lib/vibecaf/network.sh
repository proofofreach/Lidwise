#!/bin/bash
# Read-only network observation. Sourced by vibecaf.
#
# This module observes every route. It never changes Wi-Fi radio or IPv4
# configuration because current macOS exposes no safe lease-renewal operation.

NETLOG_MAX_LINES=${VIBECAF_NETLOG_MAX_LINES:-500}
RADIO_OFF_COOLDOWN=${VIBECAF_RADIO_OFF_COOLDOWN:-900}
NETWATCH_MAX_TICKS=${VIBECAF_NETWATCH_MAX_TICKS:-0}

network_uint() { case "${1:-}" in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac; [ "${#1}" -le 10 ]; }

network_log_trim() {
  local lines tmp
  network_uint "$NETLOG_MAX_LINES" || return 0
  lines=$(wc -l < "$NETLOG" 2>/dev/null | tr -d '[:space:]')
  [ -n "$lines" ] || lines=0
  network_uint "$lines" || return 0
  [ "$lines" -le "$NETLOG_MAX_LINES" ] && return 0
  tmp=$(mktemp "${NETLOG}.trim.XXXXXX") || return 0
  tail -n "$NETLOG_MAX_LINES" "$NETLOG" > "$tmp" 2>/dev/null && mv -f "$tmp" "$NETLOG"
  rm -f "$tmp"
}

netlog() {
  secure_dir "$(dirname "$NETLOG")" || return 0
  [ ! -L "$NETLOG" ] || return 0
  (umask 077; touch "$NETLOG") || return 0
  chmod 0600 "$NETLOG" || return 0
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$NETLOG"
  network_log_trim
}

associated() { "$IPCONFIG" getsummary "$1" 2>/dev/null | grep -qE '^[[:space:]]*SSID[[:space:]]*:'; }
network_route_interface() { "$ROUTE" -n get default 2>/dev/null | awk '/interface:/{print $2; exit}'; }
network_default_gateway() { "$ROUTE" -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}'; }

on_hotspot() {
  local dev=${1:-}
  [ -n "$dev" ] || dev=$(wifi_device)
  case "$("$IPCONFIG" getifaddr "$dev" 2>/dev/null)" in "$HOTSPOT_SUBNET"*) return 0 ;; esac
  return 1
}

# Tokens are intentionally machine-readable. `cheap_net` supplies the human
# text used by the status card.
network_valid_token() {
  case "${1:-}" in online|portal|deadlink|noip|unassoc|radio_off|unknown) return 0 ;; esac
  return 1
}

link_state() { # link_state [wifi BSD device]
  local dev=${1:-} route_if gateway code body tmp
  [ -n "$dev" ] || dev=$(wifi_device)
  route_if=$(network_route_interface)
  gateway=$(network_default_gateway)
  # If another interface owns the route, Wi-Fi state is not a diagnosis of
  # this connection. The probe remains read-only and reports its result.
  if [ -z "$route_if" ] || [ "$route_if" = "$dev" ]; then
    if [ -n "$dev" ]; then
      if [ "$("$NETWORKSETUP" -getairportpower "$dev" 2>/dev/null | awk '{print $NF}')" = Off ]; then
        echo radio_off; return
      fi
      if ! associated "$dev"; then echo unassoc; return; fi
      if [ -z "$("$IPCONFIG" getifaddr "$dev" 2>/dev/null)" ] || [ -z "$gateway" ]; then
        echo noip; return
      fi
    fi
  fi
  tmp=$(mktemp "$RUNTIME_DIR/vibecaf-probe.XXXXXX" 2>/dev/null) || tmp=""
  code=$("$CURL" -s -o "${tmp:-/dev/null}" -w '%{http_code}' --max-time 6 "$PROBE_URL" 2>/dev/null) || code=000
  if [ -n "$tmp" ]; then body=$(cat "$tmp" 2>/dev/null); rm -f "$tmp"; else body=""; fi
  case "$body" in *Success*) echo online ;; *) case "$code" in ''|000) echo deadlink ;; *) echo portal ;; esac ;; esac
}

net_words() {
  case "$1" in
    online) echo online ;; portal) echo 'captive portal — needs a browser login' ;;
    deadlink) echo 'link up, no internet' ;; noip) echo 'no IP address' ;;
    unassoc) echo 'not associated' ;; radio_off) echo 'Wi-Fi off' ;; *) echo unknown ;;
  esac
}

publish_net() { # publish_net <token>
  local token=$1 tmp
  network_valid_token "$token" || token=unknown
  [ ! -L "$NETSTATEFILE" ] || return 1
  tmp=$(mktemp "${NETSTATEFILE}.XXXXXX") || return 1
  if printf '%s\t%s\n' "$(date +%s)" "$token" > "$tmp" && chmod 0600 "$tmp" && mv -f "$tmp" "$NETSTATEFILE"; then return 0; fi
  rm -f "$tmp"
  return 1
}

network_cache_read() { # stdout: timestamp<TAB>token
  local ts token extra now max_age
  [ -f "$NETSTATEFILE" ] && [ ! -L "$NETSTATEFILE" ] || return 1
  IFS=$'\t' read -r ts token extra < "$NETSTATEFILE" 2>/dev/null || return 1
  [ -z "${extra:-}" ] && network_uint "$ts" && network_valid_token "$token" || return 1
  now=$(date +%s); max_age=$(( CHECK_EVERY * 3 ))
  [ "$ts" -le "$now" ] && [ $((now - ts)) -le "$max_age" ] || return 1
  printf '%s\t%s\n' "$ts" "$token"
}

network_status_token() {
  local ts token
  IFS=$'\t' read -r ts token < <(network_cache_read) || { echo unknown; return; }
  printf '%s\n' "$token"
}

cheap_net() { net_words "$(network_status_token)"; }
network_recovery_enabled() { case "${NETWORK_RECOVERY:-${VIBECAF_NETWORK_RECOVERY:-on}}" in on|1|true|yes) return 0 ;; *) return 1 ;; esac; }
# This is intentionally false until macOS provides a documented, configuration-
# preserving repair operation. The setting controls monitoring, not mutations.
network_recovery_available() { return 1; }
network_recovery_detail() {
  if network_recovery_enabled; then echo 'Network monitoring only — automatic recovery unavailable'
  else echo 'Network monitoring off'; fi
}

notify_network_transition() {
  local previous=${1:-} current=${2:-}
  [ -n "$previous" ] && [ "$previous" != "$current" ] || return 0
  case "$current" in
    online) notify_event 'Network recovered' 'Internet access is available again' ;;
    portal) notify_event 'Captive portal' 'Log in with a browser to get back online' ;;
    deadlink) notify_event 'Network degraded' 'Link is up, but the internet is unreachable' ;;
    noip) notify_event 'Lost IP address' 'Joined, but the DHCP lease is gone' ;;
    unassoc) notify_event 'Network disconnected' 'Wi-Fi is not joined to any network' ;;
    radio_off) notify_event 'Wi-Fi is off' 'The radio is powered down' ;;
  esac
}

# This retains an actionable diagnostic seam for callers without pretending it
# can repair the lease. `-setdhcp` is excluded because it rewrites a service.
dhcp_renew() {
  local svc
  svc=$(wifi_service "$1")
  [ -n "$svc" ] || return 1
  netlog "DHCP lease missing on $svc; automatic renewal is unsupported — open Network settings to renew"
  return 1
}

network_sleep() { [ "${VIBECAF_NETWATCH_NO_SLEEP:-0}" = 1 ] || sleep "$1"; }

# The loop is bounded observation. It observes portal, upstream, Ethernet, VPN,
# unknown-probe, radio-off, and lease failures without changing networking.
netwatch_loop() {
  local dev st last_st='' route_if noip_reported=0 radio_off_until=0 ticks=0 now
  dev=$(wifi_device)
  [ -n "$dev" ] || { netlog 'no Wi-Fi interface found; watchdog exiting'; return 0; }
  netlog "watchdog started on $dev ($(network_recovery_detail))"
  while :; do
    st=$(link_state "$dev"); publish_net "$st"; notify_network_transition "$last_st" "$st"
    [ -z "$last_st" ] || [ "$last_st" = "$st" ] || netlog "state: $last_st -> $st"
    last_st=$st; ticks=$((ticks + 1)); now=$(date +%s)
    if ! network_recovery_enabled; then
      netlog 'network monitoring disabled; observing this final tick only'
    else
      route_if=$(network_route_interface)
      case "$st" in
        online) noip_reported=0; radio_off_until=0 ;;
        radio_off)
          # There is no reliable way to identify intent. Treat radio-off as
          # manual and never turn the radio on from this monitor.
          if [ "$radio_off_until" -le "$now" ]; then radio_off_until=$((now + RADIO_OFF_COOLDOWN)); netlog "Wi-Fi is off; respecting manual state for ${RADIO_OFF_COOLDOWN}s"; fi ;;
        noip)
          if { [ -z "$route_if" ] || [ "$route_if" = "$dev" ]; } && [ "$noip_reported" -eq 0 ]; then
            noip_reported=1; dhcp_renew "$dev" || true
          else
            netlog "no IP on non-Wi-Fi path (${route_if:-none}); staying passive"
          fi ;;
        unassoc) netlog "Wi-Fi is not associated on ${route_if:-no default route}; open Wi-Fi settings to reconnect" ;;
        portal|deadlink) netlog "$st on ${route_if:-no default route}; passive observation only" ;;
        *) netlog "network state $st; passive observation only" ;;
      esac
    fi
    [ "$NETWATCH_MAX_TICKS" -gt 0 ] 2>/dev/null && [ "$ticks" -ge "$NETWATCH_MAX_TICKS" ] && return 0
    network_sleep "$CHECK_EVERY"
  done
}

network_session_id() { printf '%s' "${session_id:-${SESSION_ID:-}}"; }
start_network_monitor() {
  [ "${VIBECAF_NO_NETWATCH:-0}" = 1 ] && return 0
  netwatch_pid >/dev/null 2>&1 && return 0
  mkdir -p "$(dirname "$NETLOG")" || return 1
  nohup "$SELF" __netwatch 9>&- >/dev/null 2>&1 &
  if command -v process_record_write >/dev/null 2>&1; then process_record_write "$NETPIDFILE" "$!" netwatch "$(network_session_id)"
  else printf '%s\n' "$!" > "$NETPIDFILE"; fi
}

stop_network_monitor() {
  if command -v process_record_signal >/dev/null 2>&1; then process_record_signal "$NETPIDFILE" netwatch "$(network_session_id)" TERM || true
  else local pid; if pid=$(netwatch_pid); then kill "$pid" 2>/dev/null || true; fi; fi
  rm -f "$NETPIDFILE" "$NETSTATEFILE"; netlog 'watchdog stopped'
}

# Compatibility while core migrates callers.
start_netwatch() { start_network_monitor; }
stop_netwatch() { stop_network_monitor; }
