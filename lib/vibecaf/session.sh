#!/bin/bash
# Private state, process identity, locking, and owned-session primitives.

path_uid() { stat -f %u "$1" 2>/dev/null || stat -c %u "$1" 2>/dev/null; }
path_mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null; }
path_inode() { stat -f %i "$1" 2>/dev/null || stat -c %i "$1" 2>/dev/null; }

private_dir_valid() {
  local dir=$1 owner mode
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  owner=$(path_uid "$dir") || return 1; mode=$(path_mode "$dir") || return 1
  [ "$owner" = "$USER_ID" ] && [ "$mode" = 700 ]
}

secure_dir() {
  local dir=$1 owner
  [ ! -L "$dir" ] || return 1
  if [ -e "$dir" ]; then [ -d "$dir" ] || return 1; else mkdir -p "$dir" || return 1; fi
  [ ! -L "$dir" ] || return 1
  owner=$(path_uid "$dir") || return 1
  [ "$owner" = "$USER_ID" ] || return 1
  chmod 700 "$dir"
}

runtime_init() {
  secure_dir "$RUNTIME_DIR" || { echo "Unsafe runtime directory: $RUNTIME_DIR" >&2; return 1; }
}
runtime_is_secure() { private_dir_valid "$RUNTIME_DIR"; }

state_init() {
  secure_dir "$STATE_DIR" && secure_dir "$SESSION_DIR" && secure_dir "$CONFIG_DIR" &&
    secure_dir "$GOALS_DIR" && secure_dir "$AGENTS_DIR" && secure_dir "$LOG_DIR"
}

runtime_file() {
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s\n' "$RUNTIME_DIR" "$1"
}

valid_uint() {
  case "${1:-}" in ''|*[!0-9]*|???????????????????*) return 1 ;; *) return 0 ;; esac
}
uint_normalize() {
  local value=$1
  valid_uint "$value" || return 1
  while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do value=${value#0}; done
  printf '%s' "$value"
}
valid_duration() { local value; value=$(uint_normalize "${1:-}") || return 1; [ "$value" -ge 1 ] && [ "$value" -le 21600 ]; }
valid_percent() { local value; value=$(uint_normalize "${1:-}") || return 1; [ "$value" -ge 1 ] && [ "$value" -le 100 ]; }
valid_bool() { case "${1:-}" in 0|1) return 0 ;; *) return 1 ;; esac; }
valid_session_id() { case "${1:-}" in ''|*[!A-Za-z0-9._-]*) return 1 ;; *) return 0 ;; esac; }

write_field() {
  local dir=$1 field=$2 value=$3 tmp
  case "$field" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$value" in *$'\n'*|*$'\r'*) return 1 ;; esac
  secure_dir "$dir" || return 1
  tmp=$(mktemp "$dir/.$field.XXXXXX") || return 1
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s\n' "$value" > "$tmp" && mv -f "$tmp" "$dir/$field" || { rm -f "$tmp"; return 1; }
}

read_field() {
  local file="$1/$2" value owner
  private_dir_valid "$1" || { printf '%s' "${3:-}"; return; }
  [ -f "$file" ] && [ ! -L "$file" ] || { printf '%s' "${3:-}"; return; }
  value=$(sed -n '1p' "$file" 2>/dev/null) || value="${3:-}"
  printf '%s' "$value"
}

read_uint() {
  local value fallback=${3:-0}
  value=$(read_field "$1" "$2" "$fallback")
  value=$(uint_normalize "$value" 2>/dev/null) || value=$fallback
  printf '%s' "$value"
}

config_duration() {
  local value
  value=$(read_field "$CONFIG_DIR" duration "$DEFAULT_DURATION")
  if valid_duration "$value"; then value=$(uint_normalize "$value"); else value=21600; fi
  printf '%s' "$value"
}

config_recovery() {
  local value
  value=$(read_field "$CONFIG_DIR" recovery 1); valid_bool "$value" || value=1; printf '%s' "$value"
}

config_notifications() {
  local value
  value=$(read_field "$CONFIG_DIR" notifications "${VIBECAF_AGENT_NOTIFY:-0}")
  valid_bool "$value" || value=0; printf '%s' "$value"
}

process_start_identity() { "$PS" -p "$1" -o lstart= 2>/dev/null | awk '{$1=$1; print; exit}'; }
process_command() { "$PS" -p "$1" -o command= 2>/dev/null | sed -n '1p'; }

role_marker() {
  case "$1" in
    caffeinate) printf '%s' "$CAFFEINATE" ;; guard) printf '%s' '__guard' ;;
    netwatch) printf '%s' '__netwatch' ;; observation) printf '%s' '__observation' ;;
    lock) printf '%s' "$SELF" ;; *) return 1 ;;
  esac
}

process_identity_matches() {
  local pid=$1 expected_start=$2 role=$3 actual_start command marker
  valid_uint "$pid" && [ "$pid" -gt 1 ] || return 1
  actual_start=$(process_start_identity "$pid")
  [ -n "$actual_start" ] && [ "$actual_start" = "$expected_start" ] || return 1
  marker=$(role_marker "$role") || return 1
  command=$(process_command "$pid")
  printf '%s' "$command" | grep -F -- "$marker" >/dev/null 2>&1
}

process_record_write() {
  local file=$1 pid=$2 role=$3 session=$4 start="" tmp tries=0
  runtime_init || return 1; valid_session_id "$session" || return 1
  while [ "$tries" -lt 20 ]; do
    start=$(process_start_identity "$pid")
    [ -n "$start" ] && process_identity_matches "$pid" "$start" "$role" && break
    sleep 0.05; tries=$((tries + 1))
  done
  [ -n "$start" ] && process_identity_matches "$pid" "$start" "$role" || return 1
  [ ! -L "$file" ] || rm -f "$file"
  tmp=$(mktemp "$RUNTIME_DIR/.process.XXXXXX") || return 1; chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s|%s|%s|%s\n' "$pid" "$role" "$session" "$start" > "$tmp" && mv -f "$tmp" "$file" || {
    rm -f "$tmp"; return 1;
  }
}

process_record_matches() {
  local file=$1 expected_role=$2 expected_session=${3:-} pid role session start extra
  runtime_is_secure || return 1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  IFS='|' read -r pid role session start extra < "$file" || return 1
  [ -z "${extra:-}" ] && [ "$role" = "$expected_role" ] || return 1
  [ -z "$expected_session" ] || [ "$session" = "$expected_session" ] || return 1
  process_identity_matches "$pid" "$start" "$role" || return 1
  printf '%s\n' "$pid"
}

process_record_signal() {
  local file=$1 role=$2 session=${3:-} signal=${4:-TERM} pid record_role record_session start extra tries=0
  if ! pid=$(process_record_matches "$file" "$role" "$session"); then rm -f "$file"; return 0; fi
  IFS='|' read -r pid record_role record_session start extra < "$file" || return 1
  if [ "$pid" = "$$" ]; then rm -f "$file"; return 0; fi
  kill -"$signal" "$pid" 2>/dev/null || process_identity_matches "$pid" "$start" "$role" || {
    rm -f "$file"; return 0;
  }
  while process_identity_matches "$pid" "$start" "$role" && [ "$tries" -lt 20 ]; do
    sleep 0.05; tries=$((tries + 1))
  done
  if process_identity_matches "$pid" "$start" "$role" && [ "$signal" != KILL ]; then
    kill -KILL "$pid" 2>/dev/null || return 1
    tries=0
    while process_identity_matches "$pid" "$start" "$role" && [ "$tries" -lt 20 ]; do
      sleep 0.05; tries=$((tries + 1))
    done
  fi
  process_identity_matches "$pid" "$start" "$role" && return 1
  rm -f "$file"
}

legacy_session_record_valid() {
  local owned started heartbeat deadline duration
  [ -f "$SESSION_DIR/owned" ] && [ -f "$SESSION_DIR/active" ] || return 1
  owned=$(read_field "$SESSION_DIR" owned); started=$(read_field "$SESSION_DIR" started "$owned")
  heartbeat=$(read_field "$SESSION_DIR" heartbeat); deadline=$(read_field "$SESSION_DIR" deadline)
  owned=$(uint_normalize "$owned") || return 1; started=$(uint_normalize "$started") || return 1
  heartbeat=$(uint_normalize "$heartbeat") || return 1; deadline=$(uint_normalize "$deadline") || return 1
  [ "$deadline" -ge "$started" ] || return 1; duration=$((deadline-started)); [ "$duration" -ge 1 ] && [ "$duration" -le 21600 ]
}
legacy_session_valid() {
  local deadline now
  legacy_session_record_valid || return 1
  deadline=$(read_uint "$SESSION_DIR" deadline 0); now=$(date +%s); [ "$deadline" -gt "$now" ]
}
legacy_session_residue() { [ -f "$SESSION_DIR/owned" ] || [ -f "$SESSION_DIR/active" ]; }
legacy_enabling_valid() {
  local owned pid now age
  [ -f "$SESSION_DIR/owned" ] && [ -f "$SESSION_DIR/enabling-pid" ] && [ ! -f "$SESSION_DIR/active" ] || return 1
  owned=$(read_uint "$SESSION_DIR" owned 0); pid=$(read_uint "$SESSION_DIR" enabling-pid 0); now=$(date +%s); age=$((now-owned))
  [ "$owned" -gt 0 ] && [ "$pid" -gt 1 ] && [ "$age" -ge 0 ] && [ "$age" -lt "$ACTIVATION_GRACE" ]
}
modern_session_owned() {
  local id state
  id=$(read_field "$SESSION_DIR" id); state=$(read_field "$SESSION_DIR" state)
  valid_session_id "$id" && case "$state" in enabling|active) return 0 ;; *) return 1 ;; esac
}
modern_session_residue() {
  [ -f "$SESSION_DIR/id" ] || [ -f "$SESSION_DIR/state" ] || [ -f "$SESSION_DIR/started_at" ]
}
ownership_residue_unknown() {
  if modern_session_residue && ! modern_session_owned; then return 0; fi
  if legacy_session_residue && ! legacy_session_record_valid && ! legacy_enabling_valid; then return 0; fi
  return 1
}
current_session_id() {
  local id owned
  id=$(read_field "$SESSION_DIR" id)
  if valid_session_id "$id"; then printf '%s' "$id"; return; fi
  if legacy_session_valid || legacy_enabling_valid; then owned=$(read_uint "$SESSION_DIR" owned 0); printf 'legacy-%s' "$owned"; fi
}
our_caffeinate_pid() { process_record_matches "$PIDFILE" caffeinate "${1:-$(current_session_id)}"; }
netwatch_pid() { process_record_matches "$NETPIDFILE" netwatch "${1:-$(current_session_id)}"; }
guard_pid() { process_record_matches "$GUARDPIDFILE" guard "${1:-$(current_session_id)}"; }

lock_acquire() {
  local token file rc
  runtime_init || return 1
  [ ! -L "$LOCK_DIR" ] || { echo "Unsafe session lock." >&2; return 1; }
  token="$$.$RANDOM.$(date +%s)"; file=$(runtime_file "lock-contender.$token") || return 1
  process_record_write "$file" "$$" lock "$token" || return 1
  LOCK_CONTENDER=$file
  exec 9>> "$LOCK_DIR" || { rm -f "$file"; return 1; }
  chmod 600 "$LOCK_DIR" || { exec 9>&-; rm -f "$file"; return 1; }
  if [ ! -x "$LOCKF" ]; then exec 9>&-; rm -f "$file"; echo "Required kernel lock utility is unavailable: $LOCKF" >&2; return 1; fi
  "$LOCKF" -s -t 5 9; rc=$?
  case "$rc" in
    0) ;;
    64) exec 9>&-; rm -f "$file"; echo "This macOS version does not support the required kernel lock mode." >&2; return 1 ;;
    *) exec 9>&-; rm -f "$file"; echo "Another vibecaf command is still running." >&2; return 1 ;;
  esac
  trap 'lock_release' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

lock_release() {
  [ -z "${LOCK_CONTENDER:-}" ] || rm -f "$LOCK_CONTENDER"
  exec 9>&-
  trap - EXIT HUP INT TERM
}

recovery_lock_allowed() {
  local now state started deadline heartbeat age
  session_owned || return 1
  if modern_session_owned && ! session_valid; then return 0; fi
  now=$(date +%s); state=$(read_field "$SESSION_DIR" state); deadline=$(read_uint "$SESSION_DIR" deadline 0)
  [ "$deadline" -gt 0 ] || return 0
  [ "$now" -ge "$deadline" ] && return 0
  if [ "$state" = enabling ]; then
    started=$(read_uint "$SESSION_DIR" started_at 0); age=$((now-started))
    [ "$started" -eq 0 ] || [ "$age" -lt 0 ] || [ "$age" -ge "$ACTIVATION_GRACE" ]
  else
    heartbeat=$(read_uint "$SESSION_DIR" heartbeat 0); age=$((now-heartbeat))
    [ "$heartbeat" -eq 0 ] || [ "$age" -lt 0 ] || [ "$age" -gt "$GUARDIAN_GRACE" ]
  fi
}

process_identity_same() {
  local pid=$1 expected_start=$2 actual_start
  valid_uint "$pid" && [ "$pid" -gt 1 ] || return 1
  actual_start=$(process_start_identity "$pid")
  [ -n "$actual_start" ] && [ "$actual_start" = "$expected_start" ]
}

descendant_pids() {
  "$PS" -axo pid=,ppid= 2>/dev/null | awk -v root="$1" '
    { pid[NR]=$1; parent[NR]=$2 }
    END {
      found[root]=1
      for (pass=1; pass<=NR; pass++)
        for (i=1; i<=NR; i++) if (found[parent[i]]) found[pid[i]]=1
      for (i=NR; i>=1; i--) if (pid[i] != root && found[pid[i]]) print pid[i]
    }'
}

tree_records_alive() {
  local file=$1 pid start
  while IFS='|' read -r pid start; do
    process_identity_same "$pid" "$start" && return 0
  done < "$file"
  return 1
}

quiesce_process_tree() {
  local root=$1 root_start=$2 tree list previous="" pid start tries=0 stop_failed=0
  tree=$(mktemp "$RUNTIME_DIR/.recovery-tree.XXXXXX") || return 1
  chmod 600 "$tree" || { rm -f "$tree"; return 1; }
  process_identity_same "$root" "$root_start" || { rm -f "$tree"; return 0; }
  if ! kill -STOP "$root" 2>/dev/null; then
    process_identity_same "$root" "$root_start" || { rm -f "$tree"; return 0; }
    rm -f "$tree"; return 1
  fi
  while [ "$tries" -lt 20 ]; do
    list=$(descendant_pids "$root")
    for pid in $list; do
      start=$(process_start_identity "$pid")
      if [ -n "$start" ] && process_identity_same "$pid" "$start"; then
        kill -STOP "$pid" 2>/dev/null || { process_identity_same "$pid" "$start" && stop_failed=1; }
      fi
    done
    [ "$list" = "$previous" ] && break
    previous=$list; tries=$((tries + 1)); sleep 0.01
  done
  if [ "$tries" -ge 20 ] || [ "$stop_failed" -ne 0 ]; then
    for pid in $list; do kill -CONT "$pid" 2>/dev/null || true; done
    kill -CONT "$root" 2>/dev/null || true
    rm -f "$tree"; return 1
  fi
  for pid in $list; do
    start=$(process_start_identity "$pid")
    [ -n "$start" ] && process_identity_same "$pid" "$start" && printf '%s|%s\n' "$pid" "$start" >> "$tree"
  done
  while IFS='|' read -r pid start; do
    process_identity_same "$pid" "$start" || continue
    kill -TERM "$pid" 2>/dev/null || true; kill -CONT "$pid" 2>/dev/null || true
  done < "$tree"
  process_identity_same "$root" "$root_start" && kill -TERM "$root" 2>/dev/null || true
  kill -CONT "$root" 2>/dev/null || true
  tries=0
  while { process_identity_same "$root" "$root_start" || tree_records_alive "$tree"; } && [ "$tries" -lt 20 ]; do
    sleep 0.05; tries=$((tries + 1))
  done
  while IFS='|' read -r pid start; do
    process_identity_same "$pid" "$start" && kill -KILL "$pid" 2>/dev/null || true
  done < "$tree"
  process_identity_same "$root" "$root_start" && kill -KILL "$root" 2>/dev/null || true
  tries=0
  while { process_identity_same "$root" "$root_start" || tree_records_alive "$tree"; } && [ "$tries" -lt 20 ]; do
    sleep 0.05; tries=$((tries + 1))
  done
  if process_identity_same "$root" "$root_start" || tree_records_alive "$tree"; then rm -f "$tree"; return 1; fi
  rm -f "$tree"
}

lock_reclaim_for_recovery() {
  local file pid role token start extra
  recovery_lock_allowed || return 1
  for file in "$RUNTIME_DIR"/lock-contender.*; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    IFS='|' read -r pid role token start extra < "$file" || pid=""
    if [ -z "${extra:-}" ] && [ "$role" = lock ] && process_identity_matches "$pid" "$start" lock; then
      quiesce_process_tree "$pid" "$start" || return 1
    fi
    rm -f "$file"
  done
}

session_valid() {
  local id state started deadline duration floor recovery notifications
  id=$(read_field "$SESSION_DIR" id); state=$(read_field "$SESSION_DIR" state)
  started=$(read_field "$SESSION_DIR" started_at); deadline=$(read_field "$SESSION_DIR" deadline)
  duration=$(read_field "$SESSION_DIR" duration_seconds); floor=$(read_field "$SESSION_DIR" battery_floor)
  recovery=$(read_field "$SESSION_DIR" recovery); notifications=$(read_field "$SESSION_DIR" notifications)
  valid_session_id "$id" && case "$state" in enabling|active) true ;; *) false ;; esac &&
    valid_uint "$started" && valid_uint "$deadline" && valid_duration "$duration" || return 1
  started=$(uint_normalize "$started"); deadline=$(uint_normalize "$deadline"); duration=$(uint_normalize "$duration")
  floor=$(uint_normalize "$floor" 2>/dev/null) || return 1
  recovery=$(uint_normalize "$recovery" 2>/dev/null) || return 1
  notifications=$(uint_normalize "$notifications" 2>/dev/null) || return 1
  [ "$deadline" -eq $((started + duration)) ] && valid_percent "$floor" &&
    valid_bool "$recovery" && valid_bool "$notifications"
}

session_active() { { modern_session_owned && [ "$(read_field "$SESSION_DIR" state)" = active ]; } || legacy_session_valid; }
session_owned() { modern_session_owned || legacy_session_valid || legacy_enabling_valid; }
session_claim_current() { [ "$(current_session_id)" = "$1" ] && modern_session_owned && [ "$(read_field "$SESSION_DIR" state)" = enabling ]; }

session_claim() {
  local id=$1 now=$2 duration=$3 start
  state_init || return 1; start=$(process_start_identity $$)
  write_field "$SESSION_DIR" id "$id" && write_field "$SESSION_DIR" state enabling &&
    write_field "$SESSION_DIR" started_at "$now" && write_field "$SESSION_DIR" deadline "$((now + duration))" &&
    write_field "$SESSION_DIR" duration_seconds "$duration" && write_field "$SESSION_DIR" battery_floor "$BATTERY_FLOOR" &&
    write_field "$SESSION_DIR" recovery "$(config_recovery)" && write_field "$SESSION_DIR" notifications "$(config_notifications)" &&
    write_field "$SESSION_DIR" heartbeat "$now" && write_field "$SESSION_DIR" thermal-strikes 0 &&
    write_field "$SESSION_DIR" enabling_pid "$$" && write_field "$SESSION_DIR" enabling_start "$start"
}

session_activate() {
  local id
  id=$(current_session_id); valid_session_id "$id" || return 1
  write_field "$SESSION_DIR" state active && write_field "$SESSION_DIR" recovery_verified_session "$id" &&
    write_field "$SESSION_DIR" recovery_verified_at "$(date +%s)" &&
    rm -f "$SESSION_DIR/enabling_pid" "$SESSION_DIR/enabling_start" "$SESSION_DIR/last-alert"
}

session_touch() { session_active && write_field "$SESSION_DIR" heartbeat "$(date +%s)"; }

session_clear() {
  secure_dir "$SESSION_DIR" || return 1
  rm -f "$SESSION_DIR/id" "$SESSION_DIR/state" "$SESSION_DIR/started_at" "$SESSION_DIR/deadline" \
    "$SESSION_DIR/duration_seconds" "$SESSION_DIR/battery_floor" "$SESSION_DIR/recovery" \
    "$SESSION_DIR/notifications" "$SESSION_DIR/heartbeat" "$SESSION_DIR/thermal-strikes" \
    "$SESSION_DIR/recovery_verified_at" "$SESSION_DIR/recovery_verified_session" \
    "$SESSION_DIR/recovery_failed_at" "$SESSION_DIR/recovery_failed_session" \
    "$SESSION_DIR/guardian_session" "$SESSION_DIR/guardian_heartbeat" \
    "$SESSION_DIR/enabling_pid" "$SESSION_DIR/enabling_start" \
    "$SESSION_DIR/last-alert" "$SESSION_DIR/active" "$SESSION_DIR/owned" "$SESSION_DIR/started"
}

session_enabler_alive() {
  process_identity_matches "$(read_field "$SESSION_DIR" enabling_pid)" "$(read_field "$SESSION_DIR" enabling_start)" lock
}
