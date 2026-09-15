#!/bin/bash
# Optional work observation. Sourced by lidwise.

# ── goal registry ────────────────────────────────────────────────────────────
#
# Goals are observations inside an awake work window. They never own that
# window and no goal transition calls turn_on or turn_off.

goal_id() { printf '%s' "$1" | /usr/bin/shasum -a 256 | awk '{print substr($1,1,16)}'; }

goal_dir() { printf '%s/%s\n' "$GOALS_DIR" "$(goal_id "$1")"; }

valid_goal_name() {
  [ -n "$1" ] || return 1
  case "$1" in *$'\n'*|*$'\t'*) return 1 ;; esac
}

goal_add() {
  local name=${1:-} dir now pid="" activity_file="" stale_after=0
  valid_goal_name "$name" || { echo "goal name must be non-empty and contain no tabs or newlines" >&2; return 2; }
  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pid)
        [ "$#" -ge 2 ] || { echo "--pid requires a value" >&2; return 2; }
        pid=$2; shift 2 ;;
      --activity-file)
        [ "$#" -ge 2 ] || { echo "--activity-file requires a path" >&2; return 2; }
        activity_file=$2; shift 2 ;;
      --stale-after)
        [ "$#" -ge 2 ] || { echo "--stale-after requires seconds" >&2; return 2; }
        stale_after=$2; shift 2 ;;
      *) echo "unknown goal option: $1" >&2; return 2 ;;
    esac
  done
  case "$pid" in
    "") ;;
    *[!0-9]*|0) echo "pid must be a positive integer" >&2; return 2 ;;
  esac
  case "$stale_after" in *[!0-9]*) echo "stale-after must be a non-negative integer" >&2; return 2 ;; esac
  dir=$(goal_dir "$name"); now=$(date +%s)
  write_field "$dir" name "$name"
  write_field "$dir" state active
  write_field "$dir" message ""
  write_field "$dir" updated_at "$now"
  write_field "$dir" observed active
  write_field "$dir" pid "$pid"
  write_field "$dir" activity_file "$activity_file"
  write_field "$dir" stale_after "$stale_after"
  echo "goal added: $name"
}

goal_transition() {  # goal_transition <state> <name> [message]
  local state=$1 name=${2:-} message=${3:-} dir previous title
  dir=$(goal_dir "$name")
  [ -d "$dir" ] || { echo "unknown goal: $name" >&2; return 1; }
  previous=$(read_field "$dir" observed unknown)
  write_field "$dir" state "$state"
  write_field "$dir" observed "$state"
  write_field "$dir" message "$message"
  write_field "$dir" updated_at "$(date +%s)"
  if [ "$previous" != "$state" ]; then
    case "$state" in
      completed) title="Goal completed" ;;
      failed) title="Goal failed" ;;
      active) title="Goal active" ;;
      *) title="Goal changed" ;;
    esac
    notify_event "$title" "$name${message:+: $message}"
  fi
  echo "goal $state: $name"
}

goal_remove() {
  local name=${1:-} dir
  valid_goal_name "$name" || { echo "goal name is required" >&2; return 2; }
  dir=$(goal_dir "$name")
  [ -d "$dir" ] || { echo "unknown goal: $name" >&2; return 1; }
  rm -rf "$dir"
  echo "goal removed: $name"
}

goal_restart() {
  local name=${1:-} dir
  dir=$(goal_dir "$name")
  [ -d "$dir" ] || { echo "unknown goal: $name" >&2; return 1; }
  goal_add "$@" >/dev/null
  echo "goal restarted: $name"
}

goal_activity_time() {
  local dir=$1 activity_file updated
  activity_file=$(read_field "$dir" activity_file)
  if [ -n "$activity_file" ] && [ -e "$activity_file" ]; then
    stat -f %m "$activity_file" 2>/dev/null && return
  fi
  updated=$(read_uint "$dir" updated_at 0)
  printf '%s\n' "$updated"
}

goal_refresh() {
  local dir=$1 declared previous next message pid stale_after last now age title name
  declared=$(read_field "$dir" state active)
  previous=$(read_field "$dir" observed unknown)
  next=$declared; message=$(read_field "$dir" message)

  if [ "$declared" = "active" ]; then
    pid=$(read_field "$dir" pid)
    stale_after=$(read_uint "$dir" stale_after 0)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      next=stopped; message="process stopped"
    elif [ "$stale_after" -gt 0 ] 2>/dev/null; then
      last=$(goal_activity_time "$dir"); now=$(date +%s); age=$((now - last))
      # Strictly greater, not >=: mtime and date +%s are whole seconds, so a
      # file touched a moment ago can already compute age=1. With >= that made
      # stale-after 1 flag activity from <1s ago as a stall (flaky in
      # test-lidwise-goal-monitoring). Tolerating one extra second is safe;
      # a false "stalled" alert is not.
      if [ "$age" -gt "$stale_after" ]; then
        next=stalled; message="no activity for ${age}s"
      else
        next=active; message=""
      fi
    else
      next=active
    fi
  fi

  if [ "$next" != "$previous" ]; then
    write_field "$dir" observed "$next"
    write_field "$dir" message "$message"
    name=$(read_field "$dir" name)
    case "$next" in
      stalled|stopped) title="Goal needs attention" ;;
      completed) title="Goal completed" ;;
      failed) title="Goal failed" ;;
      active) title="Goal active again" ;;
      *) title="Goal changed" ;;
    esac
    notify_event "$title" "$name${message:+: $message}"
  fi
}

goals_refresh() {
  local dir
  for dir in "$GOALS_DIR"/*; do
    [ -d "$dir" ] || continue
    goal_refresh "$dir"
  done
}

goals_summary() {
  local dir state active=0 stalled=0 completed=0 failed=0
  for dir in "$GOALS_DIR"/*; do
    [ -d "$dir" ] || continue
    state=$(read_field "$dir" observed unknown)
    case "$state" in
      active) active=$((active + 1)) ;;
      stalled|stopped) stalled=$((stalled + 1)) ;;
      completed) completed=$((completed + 1)) ;;
      failed) failed=$((failed + 1)) ;;
    esac
  done
  printf '%s active · %s stalled · %s completed · %s failed\n' \
    "$active" "$stalled" "$completed" "$failed"
}

goals_json() {
  local dir state active=0 stalled=0 completed=0 failed=0
  for dir in "$GOALS_DIR"/*; do
    [ -d "$dir" ] || continue
    state=$(read_field "$dir" observed unknown)
    case "$state" in
      active) active=$((active + 1)) ;;
      stalled|stopped) stalled=$((stalled + 1)) ;;
      completed) completed=$((completed + 1)) ;;
      failed) failed=$((failed + 1)) ;;
    esac
  done
  printf '{"active":%s,"stalled":%s,"completed":%s,"failed":%s}' "$active" "$stalled" "$completed" "$failed"
}

goals_list() {
  local dir name state message
  [ "${1:-}" = "--refresh" ] && { goals_refresh; shift || true; }
  [ "${1:-}" = "--summary" ] && { goals_summary; return; }
  for dir in "$GOALS_DIR"/*; do
    [ -d "$dir" ] || continue
    name=$(read_field "$dir" name)
    state=$(read_field "$dir" observed unknown)
    message=$(read_field "$dir" message)
    printf '%s\t%s\t%s\n' "$name" "$state" "$message"
  done
}

goal_command() {
  local action=${1:-}; shift || true
  case "$action" in
    add) goal_add "$@" ;;
    restart) goal_restart "$@" ;;
    touch) goal_transition active "${1:-}" "${2:-}" ;;
    complete) goal_transition completed "${1:-}" "${2:-}" ;;
    fail) goal_transition failed "${1:-}" "${2:-}" ;;
    remove) goal_remove "${1:-}" ;;
    *) echo "usage: lidwise goal <add|restart|touch|complete|fail|remove> <name> [options]" >&2; return 2 ;;
  esac
}

# ── automatic agent observation ─────────────────────────────────────────────
#
# Claude Code and Codex sessions are discovered from their local activity logs
# and running processes. This registry is telemetry only: no function in this
# section calls turn_on or turn_off.

agent_provider_name() {
  case "$1" in claude) echo "Claude Code" ;; codex) echo "Codex" ;; *) echo "$1" ;; esac
}

agent_record_dir() {
  local key
  key=$(printf '%s:%s' "$1" "$2" | /usr/bin/shasum -a 256 | awk '{print substr($1,1,16)}')
  printf '%s/%s\n' "$AGENTS_DIR" "$key"
}

AGENT_RECORD_MAX_AGE=${VIBECAF_AGENT_RECORD_MAX_AGE:-604800}
AGENT_RECORD_MAX=${VIBECAF_AGENT_RECORD_MAX:-512}
OBSERVATION_EVERY=${VIBECAF_OBSERVATION_EVERY:-60}
OBSERVATION_MAX_TICKS=${VIBECAF_OBSERVATION_MAX_TICKS:-0}

agent_valid_state() {
  case "$1" in working|waiting|quiet|finished|failed) return 0 ;; *) return 1 ;; esac
}

agent_valid_age() {
  case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

agent_valid_session() {
  [ -n "$1" ] && [ "${#1}" -le 1024 ] || return 1
  case "$1" in *$'\n'*|*$'\t'*) return 1 ;; esac
}

agent_private_dir() {
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(stat -f %u "$1" 2>/dev/null)" = "$(id -u)" ] || return 1
  case "$(stat -f %Lp "$1" 2>/dev/null)" in 700|500) return 0 ;; *) return 1 ;; esac
}

agent_private_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  [ "$(stat -f %u "$1" 2>/dev/null)" = "$(id -u)" ] || return 1
  [ "$(stat -f %Lp "$1" 2>/dev/null)" = 600 ] || return 1
  [ "$(stat -f %z "$1" 2>/dev/null || echo 999999)" -le 262144 ] 2>/dev/null
}

agents_prepare_runtime() {
  [ ! -L "$RUNTIME_DIR" ] || return 1
  if [ ! -d "$RUNTIME_DIR" ]; then mkdir -m 700 "$RUNTIME_DIR" || return 1; fi
  chmod 700 "$RUNTIME_DIR" || return 1
  agent_private_dir "$RUNTIME_DIR" || return 1
  [ ! -L "$AGENT_RUNTIME_DIR" ] || return 1
  if [ ! -d "$AGENT_RUNTIME_DIR" ]; then
    mkdir -m 700 "$AGENT_RUNTIME_DIR" || return 1
  fi
  chmod 700 "$AGENT_RUNTIME_DIR" || return 1
  agent_private_dir "$AGENT_RUNTIME_DIR" || return 1
  if [ -e "$AGENTSTATEFILE" ]; then
    [ -f "$AGENTSTATEFILE" ] && [ ! -L "$AGENTSTATEFILE" ] || return 1
    [ "$(stat -f %u "$AGENTSTATEFILE" 2>/dev/null)" = "$(id -u)" ] || return 1
    chmod 600 "$AGENTSTATEFILE" || return 1
  fi
}

agents_refresh() {
  local tmp provider session state age dir previous display title body now record_count
  agents_prepare_runtime || return 1
  [ -x "$AGENT_SCAN_CMD" ] || { rm -f "$AGENTSTATEFILE"; return 1; }
  mkdir -p "$AGENTS_DIR"
  chmod 700 "$AGENTS_DIR" 2>/dev/null || true
  agent_private_dir "$AGENTS_DIR" || return 1
  record_count=$(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed -n '1,513p' | wc -l | tr -d ' ')
  tmp=$(/usr/bin/mktemp "$AGENTSTATEFILE.XXXXXX") || return 1
  chmod 600 "$tmp"
  if ! "$AGENT_SCAN_CMD" > "$tmp"; then
    rm -f "$tmp" "$AGENTSTATEFILE"
    return 1
  fi

  while IFS=$'\t' read -r provider session state age; do
    case "$provider" in claude|codex) ;; *) continue ;; esac
    agent_valid_state "$state" || continue
    agent_valid_age "$age" || continue
    case "$provider:$state" in
      claude:working|claude:waiting|claude:quiet|claude:finished|claude:failed|codex:working|codex:waiting|codex:quiet|codex:finished|codex:failed) ;;
      *) continue ;;
    esac
    agent_valid_session "$session" || continue
    dir=$(agent_record_dir "$provider" "$session")
    if [ ! -d "$dir" ] && [ "$record_count" -ge "$AGENT_RECORD_MAX" ] 2>/dev/null; then continue; fi
    if [ ! -d "$dir" ]; then record_count=$((record_count + 1)); fi
    previous=$(read_field "$dir" state unknown)
    write_field "$dir" provider "$provider"
    write_field "$dir" session "$session"
    write_field "$dir" state "$state"
    write_field "$dir" age "$age"
    write_field "$dir" updated_at "$(date +%s)"

    [ "$previous" = "unknown" ] && continue
    [ "$previous" = "$state" ] && continue
    [ "$AGENT_NOTIFY" = "1" ] || continue
    display=$(agent_provider_name "$provider")
    case "$state:$previous" in
      working:finished) title="Agent working"; body="$display session restarted" ;;
      working:*) title="Agent working"; body="$display session resumed" ;;
      waiting:*) title="Agent needs attention"; body="$display session is waiting" ;;
      quiet:*) title="Agent quiet"; body="$display session is quiet" ;;
      finished:*) title="Agent finished"; body="$display session reported completion" ;;
      failed:*) title="Agent failed"; body="$display session reported a failure" ;;
    esac
    notify_event "$title" "$body"
  done < "$tmp"

  mv "$tmp" "$AGENTSTATEFILE"
  chmod 600 "$AGENTSTATEFILE"
  agents_prune
}

agents_prune() {
  local dir updated now age
  agent_valid_age "${AGENT_RECORD_MAX_AGE:-}" || return 0
  now=$(date +%s)
  for dir in "$AGENTS_DIR"/*; do
    [ -d "$dir" ] || continue
    updated=$(read_uint "$dir" updated_at 0)
    [ "$updated" -gt 0 ] || continue
    age=$((now - updated))
    [ "$age" -gt "$AGENT_RECORD_MAX_AGE" ] || continue
    rm -rf "$dir"
  done
}

agents_cache_current() {
  local modified now age max_age=${1:-$AGENT_CACHE_MAX_AGE}
  agents_prepare_runtime || return 1
  if agent_private_file "$AGENTSTATEFILE"; then
    modified=$(stat -f %m "$AGENTSTATEFILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    agent_valid_age "$modified" || modified=0
    age=$((now - modified))
    [ "$age" -ge 0 ] && [ "$age" -le "$max_age" ] && return 0
  fi
  return 1
}

agents_ensure_cache() {
  agents_cache_current || agents_refresh
}

agents_summary() {
  local provider state session age cw=0 cwait=0 cq=0 cf=0 cfail=0 xw=0 xwait=0 xq=0 xf=0 xfail=0
  if agents_ensure_cache && [ -f "$AGENTSTATEFILE" ]; then
    while IFS=$'\t' read -r provider session state age; do
      agent_valid_age "$age" || continue
      case "$provider:$state" in
        claude:working) cw=$((cw + 1)) ;; claude:waiting) cwait=$((cwait + 1)) ;;
        claude:quiet) cq=$((cq + 1)) ;; claude:finished) cf=$((cf + 1)) ;; claude:failed) cfail=$((cfail + 1)) ;;
        codex:working) xw=$((xw + 1)) ;; codex:waiting) xwait=$((xwait + 1)) ;;
        codex:quiet) xq=$((xq + 1)) ;; codex:finished) xf=$((xf + 1)) ;; codex:failed) xfail=$((xfail + 1)) ;;
      esac
    done < "$AGENTSTATEFILE"
  fi
  echo "Claude Code: $cw working · $cwait waiting · $cq quiet · $cf finished · $cfail failed"
  echo "Codex: $xw working · $xwait waiting · $xq quiet · $xf finished · $xfail failed"
  echo "All agents: $((cw + xw)) working · $((cwait + xwait)) waiting · $((cq + xq)) quiet · $((cf + xf)) finished · $((cfail + xfail)) failed"
}

agents_json() {
  local provider state session age cw=0 cwait=0 cq=0 cf=0 cfail=0 xw=0 xwait=0 xq=0 xf=0 xfail=0
  # Machine status never waits for optional transcript scanning.
  if agents_cache_current && [ -f "$AGENTSTATEFILE" ]; then
    while IFS=$'\t' read -r provider session state age; do
      agent_valid_age "$age" || continue
      case "$provider:$state" in
        claude:working) cw=$((cw + 1)) ;; claude:waiting) cwait=$((cwait + 1)) ;; claude:quiet) cq=$((cq + 1)) ;; claude:finished) cf=$((cf + 1)) ;; claude:failed) cfail=$((cfail + 1)) ;;
        codex:working) xw=$((xw + 1)) ;; codex:waiting) xwait=$((xwait + 1)) ;; codex:quiet) xq=$((xq + 1)) ;; codex:finished) xf=$((xf + 1)) ;; codex:failed) xfail=$((xfail + 1)) ;;
      esac
    done < "$AGENTSTATEFILE"
  fi
  printf '{"claude":{"working":%s,"waiting":%s,"quiet":%s,"finished":%s,"failed":%s},"codex":{"working":%s,"waiting":%s,"quiet":%s,"finished":%s,"failed":%s}}' "$cw" "$cwait" "$cq" "$cf" "$cfail" "$xw" "$xwait" "$xq" "$xf" "$xfail"
}

agents_list() {
  local provider session state age
  [ "${1:-}" = "--refresh" ] && agents_refresh
  [ "${1:-}" = "--summary" ] && { agents_refresh || true; agents_summary; return; }
  agents_ensure_cache || return 0
  [ -f "$AGENTSTATEFILE" ] || return 0
  while IFS=$'\t' read -r provider session state age; do
    agent_valid_age "$age" || continue
    printf '%s\t%s\t%s\t%ss ago\n' "$(agent_provider_name "$provider")" "$state" "$session" "$age"
  done < "$AGENTSTATEFILE"
}

# Agent, goal and network observation share one worker. Safety loops never wait
# for this optional work. Each kind of observation keeps its own polling cadence.
observation_now() { date +%s; }
observation_refresh_activity() {
  [ -x "$OBSERVATION_RUNNER" ] || return 1
  "$OBSERVATION_RUNNER" --run-bounded 10 "$SELF" __observation_scan
}
observation_loop() {
  local ticks=0 now next_activity=0 next_network=0 delay network_on=0 was_network_on=0
  local activity_every=${OBSERVATION_EVERY:-60} network_every=${CHECK_EVERY:-20}
  while :; do
    now=$(observation_now)
    if command -v config_notifications >/dev/null 2>&1; then AGENT_NOTIFY=$(config_notifications); fi
    network_on=0
    if [ "${VIBECAF_NO_NETWATCH:-0}" != 1 ] && command -v config_recovery >/dev/null 2>&1; then
      NETWORK_RECOVERY=$([ "$(config_recovery)" = 1 ] && echo on || echo off)
      network_recovery_enabled && network_on=1
    fi
    if [ "$network_on" != "$was_network_on" ]; then
      network_observe_reset
      next_network=0
      [ "$network_on" = 1 ] || rm -f "$NETSTATEFILE"
      was_network_on=$network_on
    fi
    if [ "$network_on" = 1 ] && [ "$now" -ge "$next_network" ]; then
      network_observe_once configured || true
      next_network=$(( $(observation_now) + network_every ))
    fi
    if [ "$now" -ge "$next_activity" ]; then
      if [ "${VIBECAF_NO_OBSERVATION:-0}" != 1 ]; then observation_refresh_activity || true; fi
      ticks=$((ticks + 1))
      next_activity=$(( $(observation_now) + activity_every ))
      [ "$OBSERVATION_MAX_TICKS" -gt 0 ] 2>/dev/null && [ "$ticks" -ge "$OBSERVATION_MAX_TICKS" ] && return 0
    fi
    now=$(observation_now)
    delay=$((next_activity - now))
    if [ "$network_on" = 1 ] && [ $((next_network - now)) -lt "$delay" ]; then delay=$((next_network - now)); fi
    # Also reload settings while network monitoring is off.
    [ "$delay" -le "$network_every" ] || delay=$network_every
    [ "$delay" -gt 0 ] || delay=1
    sleep "$delay"
  done
}
