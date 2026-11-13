#!/bin/bash
# Guardian scheduling and acknowledgement. session.sh provides state access;
# the executable provides guardian_check_once and power recovery operations.

# The durable wake request is the private guardian_wake file. The doorbell is
# only a latency optimization: a private FIFO the guardian holds open so a
# blocking builtin read returns as soon as activation rings it. Without it the
# guardian still sees the wake file within one second.
GUARDIAN_DOORBELL_FD_OPEN=0
guardian_doorbell_path() { runtime_file guardian.doorbell; }
guardian_doorbell_open() {
  local fifo
  [ -n "${RUNTIME_DIR:-}" ] || return 1
  runtime_init >/dev/null 2>&1 || return 1
  fifo=$(guardian_doorbell_path) || return 1
  rm -f "$fifo" && mkfifo -m 600 "$fifo" 2>/dev/null || return 1
  [ -p "$fifo" ] && [ ! -L "$fifo" ] || return 1
  # Read-write open never blocks and keeps the FIFO from reaching end-of-file.
  exec 7<>"$fifo" || return 1
  GUARDIAN_DOORBELL_FD_OPEN=1
}
# Never blocks: the read-write open succeeds without a reader, and a live
# guardian drains each ring. A missing or unsafe doorbell is ignored.
guardian_ring() {
  local fifo
  [ -n "${RUNTIME_DIR:-}" ] && runtime_is_secure || return 0
  fifo=$(guardian_doorbell_path) || return 0
  [ -p "$fifo" ] && [ ! -L "$fifo" ] || return 0
  { printf 'wake\n' >&8; } 8<>"$fifo" 2>/dev/null || true
}
# Wait up to one second, returning early on a ring. A read that fails without
# waiting means the descriptor is unusable; fall back to sleep so the loop can
# never spin.
guardian_pause() {
  local before=$SECONDS line
  if [ "$GUARDIAN_DOORBELL_FD_OPEN" = 1 ]; then
    read -r -t 1 -u 7 line 2>/dev/null && return 0
    [ "$SECONDS" -eq "$before" ] || return 0
    GUARDIAN_DOORBELL_FD_OPEN=0; exec 7<&- 2>/dev/null || true
  fi
  sleep 1
}

guardian_loop() {
  local waited wake_blocked watched
  guardian_doorbell_open || true
  while :; do
    # The installer can move the state folder while this daemon runs; follow it.
    if command -v state_paths_resolve >/dev/null 2>&1; then state_paths_resolve; fi
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
      if command -v state_paths_resolve >/dev/null 2>&1; then
        watched=$STATE_DIR; state_paths_resolve; [ "$STATE_DIR" = "$watched" ] || break
      fi
      if [ -f "$SESSION_DIR/guardian_wake" ] && [ ! -L "$SESSION_DIR/guardian_wake" ] &&
         private_dir_valid "$SESSION_DIR"; then break; fi
      guardian_pause
      waited=$((waited + 1))
    done
  done
}

# Best-effort, bounded acknowledgement only. Full readiness is still assessed
# by status. Call after releasing the mutation lock so reconciliation can run.
guardian_wait_for_session() {
  local expected=$1 attempts=${2:-30} heartbeat age
  valid_session_id "$expected" || return 1
  while [ "$attempts" -gt 0 ]; do
    [ "$(current_session_id)" = "$expected" ] || return 1
    heartbeat=$(read_epoch "$SESSION_DIR" guardian_heartbeat 0)
    age=$(($(date +%s) - heartbeat))
    if [ "$(read_field "$SESSION_DIR" guardian_session)" = "$expected" ] &&
       [ "$heartbeat" -gt 0 ] && [ "$age" -ge 0 ] && [ "$age" -le $((GUARDIAN_EVERY * 3)) ]; then
      [ "$(current_session_id)" = "$expected" ]; return
    fi
    sleep 0.1
    attempts=$((attempts - 1))
  done
  return 1
}
