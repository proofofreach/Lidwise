#!/bin/bash
# Guardian scheduling and acknowledgement. session.sh provides state access;
# the executable provides guardian_check_once and power recovery operations.
guardian_loop() {
  local waited wake_blocked
  while :; do
    # Consume before checking so activation during the check remains pending.
    # A rejected directory or failed unlink must never bypass the next sleep.
    wake_blocked=0
    if [ -e "$SESSION_DIR/guardian_wake" ] || [ -L "$SESSION_DIR/guardian_wake" ]; then
      if ! private_dir_valid "$SESSION_DIR" || ! rm -f "$SESSION_DIR/guardian_wake" 2>/dev/null; then
        wake_blocked=1
      elif [ -e "$SESSION_DIR/guardian_wake" ] || [ -L "$SESSION_DIR/guardian_wake" ]; then
        wake_blocked=1
      fi
    fi
    guardian_check_once || true
    if [ "$wake_blocked" = 1 ]; then sleep "$GUARDIAN_EVERY"; continue; fi
    waited=0
    while [ "$waited" -lt "$GUARDIAN_EVERY" ]; do
      if [ -f "$SESSION_DIR/guardian_wake" ] && [ ! -L "$SESSION_DIR/guardian_wake" ] &&
         private_dir_valid "$SESSION_DIR"; then break; fi
      sleep 1
      waited=$((waited + 1))
    done
  done
}

# Best-effort, bounded acknowledgement only. Full readiness is still assessed
# by status. Call after releasing the mutation lock so reconciliation can run.
guardian_wait_for_session() {
  local expected=$1 attempts=${2:-15} heartbeat age
  valid_session_id "$expected" || return 1
  while [ "$attempts" -gt 0 ]; do
    [ "$(current_session_id)" = "$expected" ] || return 1
    heartbeat=$(read_epoch "$SESSION_DIR" guardian_heartbeat 0)
    age=$(($(date +%s) - heartbeat))
    if [ "$(read_field "$SESSION_DIR" guardian_session)" = "$expected" ] &&
       [ "$heartbeat" -gt 0 ] && [ "$age" -ge 0 ] && [ "$age" -le $((GUARDIAN_EVERY * 3)) ]; then
      [ "$(current_session_id)" = "$expected" ]; return
    fi
    sleep 0.2
    attempts=$((attempts - 1))
  done
  return 1
}
