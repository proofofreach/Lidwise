#!/bin/bash
# Bounded private session history. History is diagnostic and never gates power recovery.

HISTORY_FILE="$STATE_DIR/history.tsv"
HISTORY_MAX_RECORDS=20
HISTORY_MAX_BYTES=65536
HISTORY_MAX_SCAN_ROWS=40

history_safe_text() {
  printf '%s' "$1" | tr '\t\r\n|' '    ' | cut -c 1-200
}

history_file_readable() {
  local size owner mode
  private_dir_valid "$STATE_DIR" || return 1
  [ -f "$HISTORY_FILE" ] && [ ! -L "$HISTORY_FILE" ] || return 1
  owner=$(path_uid "$HISTORY_FILE") || return 1
  mode=$(path_mode "$HISTORY_FILE") || return 1
  size=$(stat -f %z "$HISTORY_FILE" 2>/dev/null || stat -c %s "$HISTORY_FILE" 2>/dev/null) || return 1
  [ "$owner" = "$USER_ID" ] && [ "$mode" = 600 ] && [ "$size" -le "$HISTORY_MAX_BYTES" ]
}

history_record_valid() {
  local id=$1 started=$2 ended=$3 deadline=$4 reason=$5 restoration=$6 battery_start=$7 battery_end=$8 power_start=$9 power_end=${10}
  valid_session_id "$id" && [ "${#id}" -le 120 ] || return 1
  valid_epoch "$started" && valid_epoch "$ended" && valid_epoch "$deadline" || return 1
  { [ "$(uint_normalize "$deadline")" -eq 0 ] || [ "$(uint_normalize "$deadline")" -ge "$(uint_normalize "$started")" ]; } || return 1
  [ -n "$reason" ] && [ "${#reason}" -le 200 ] || return 1
  case "$reason" in *$'\t'*|*$'\r'*|*$'\n'*|*'|'*) return 1 ;; esac
  printf '%s' "$reason" | LC_ALL=C grep -q '^[ -~][ -~]*$' || return 1
  case "$restoration" in verified|failed|unknown) ;; *) return 1 ;; esac
  case "$battery_start" in -) ;; *) valid_battery_percent "$battery_start" || return 1 ;; esac
  case "$battery_end" in -) ;; *) valid_battery_percent "$battery_end" || return 1 ;; esac
  case "$power_start" in AC|Battery|unknown|-) ;; *) return 1 ;; esac
  case "$power_end" in AC|Battery|unknown|-) ;; *) return 1 ;; esac
}

history_upsert() {
  local id=$1 started=$2 ended=$3 deadline=$4 reason restoration=$6 battery_start=$7 battery_end=$8 power_start=$9 power_end=${10}
  local tmp old_id old_started old_ended old_deadline old_reason old_restoration old_battery_start old_battery_end old_power_start old_power_end extra count=1 scanned=0
  reason=$(history_safe_text "$5"); restoration=$6
  history_record_valid "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" "$battery_start" "$battery_end" "$power_start" "$power_end" || return 1
  state_init || return 1
  tmp=$(mktemp "$STATE_DIR/.history.XXXXXX") || return 1
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" "$battery_start" "$battery_end" "$power_start" "$power_end" > "$tmp" || {
      rm -f "$tmp"; return 1;
    }
  if history_file_readable; then
    while [ "$scanned" -lt "$HISTORY_MAX_SCAN_ROWS" ] &&
      IFS=$'\t' read -r old_id old_started old_ended old_deadline old_reason old_restoration old_battery_start old_battery_end old_power_start old_power_end extra; do
      scanned=$((scanned + 1))
      [ "$count" -lt "$HISTORY_MAX_RECORDS" ] || break
      [ "$old_id" = "$id" ] && continue
      [ -z "${extra:-}" ] || continue
      history_record_valid "$old_id" "$old_started" "$old_ended" "$old_deadline" "$old_reason" "$old_restoration" \
        "$old_battery_start" "$old_battery_end" "$old_power_start" "$old_power_end" || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$old_id" "$old_started" "$old_ended" "$old_deadline" "$old_reason" "$old_restoration" \
        "$old_battery_start" "$old_battery_end" "$old_power_start" "$old_power_end" >> "$tmp" || {
          rm -f "$tmp"; return 1;
        }
      count=$((count + 1))
    done < "$HISTORY_FILE"
  fi
  mv -f "$tmp" "$HISTORY_FILE"
}

history_capture_current() {
  local reason=$1 restoration=$2 id started deadline battery_start power_start blob battery_end power_end ended
  id=$(current_session_id); valid_session_id "$id" || return 1
  started=$(read_epoch "$SESSION_DIR" started_at 0); deadline=$(read_epoch "$SESSION_DIR" deadline 0)
  [ "$started" -gt 0 ] && { [ "$deadline" -eq 0 ] || [ "$deadline" -ge "$started" ]; } || return 1
  battery_start=$(read_field "$SESSION_DIR" battery_start -); valid_battery_percent "$battery_start" || battery_start=-
  power_start=$(read_field "$SESSION_DIR" power_start -)
  case "$power_start" in AC|Battery|unknown) ;; *) power_start=- ;; esac
  blob=$(batt_blob 2>/dev/null || true); battery_end=$(battery_num "$blob")
  valid_battery_percent "$battery_end" || battery_end=-
  power_end=$(power_source "$blob"); case "$power_end" in AC|Battery|unknown) ;; *) power_end=- ;; esac
  ended=$(date +%s)
  history_upsert "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
    "$battery_start" "$battery_end" "$power_start" "$power_end"
}

history_record_json() {
  local id=$1 started=$2 ended=$3 deadline=$4 reason=$5 restoration=$6 battery_start=$7 battery_end=$8 power_start=$9 power_end=${10}
  printf '{"session_id":"%s","started_at":%s,"ended_at":%s,"deadline":%s,"reason":"%s","restoration":"%s","battery_start":' \
    "$(json_escape "$id")" "$(uint_normalize "$started")" "$(uint_normalize "$ended")" "$(uint_normalize "$deadline")" "$(json_escape "$reason")" "$restoration"
  [ "$battery_start" = - ] && printf null || printf '%s' "$(uint_normalize "$battery_start")"
  printf ',"battery_end":'; [ "$battery_end" = - ] && printf null || printf '%s' "$(uint_normalize "$battery_end")"
  printf ',"power_start":'; [ "$power_start" = - ] && printf null || json_string_or_null "$power_start"
  printf ',"power_end":'; [ "$power_end" = - ] && printf null || json_string_or_null "$power_end"
  printf '}'
}

history_json_records() {
  local id started ended deadline reason restoration battery_start battery_end power_start power_end extra count=0 scanned=0
  history_file_readable || return 0
  while [ "$scanned" -lt "$HISTORY_MAX_SCAN_ROWS" ] &&
    IFS=$'\t' read -r id started ended deadline reason restoration battery_start battery_end power_start power_end extra; do
    scanned=$((scanned + 1))
    [ "$count" -lt "$HISTORY_MAX_RECORDS" ] || break
    [ -z "${extra:-}" ] || continue
    history_record_valid "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
      "$battery_start" "$battery_end" "$power_start" "$power_end" || continue
    [ "$count" -eq 0 ] || printf ','
    history_record_json "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
      "$battery_start" "$battery_end" "$power_start" "$power_end"
    count=$((count + 1))
  done < "$HISTORY_FILE"
}

history_last_json() {
  local id started ended deadline reason restoration battery_start battery_end power_start power_end extra scanned=0
  history_file_readable || { printf null; return; }
  while [ "$scanned" -lt "$HISTORY_MAX_SCAN_ROWS" ] &&
    IFS=$'\t' read -r id started ended deadline reason restoration battery_start battery_end power_start power_end extra; do
    scanned=$((scanned + 1))
    [ -z "${extra:-}" ] || continue
    history_record_valid "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
      "$battery_start" "$battery_end" "$power_start" "$power_end" || continue
    history_record_json "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
      "$battery_start" "$battery_end" "$power_start" "$power_end"
    return
  done < "$HISTORY_FILE"
  printf null
}

history_command() {
  local records
  case "$#:${1:-}" in 0:) ;;
    1:--json) records=$(history_json_records); printf '{"schema_version":1,"sessions":[%s]}\n' "$records"; return ;;
    *) echo "usage: lidwise history [--json]" >&2; return 2 ;;
  esac
  history_file_readable || { echo "No session history."; return; }
  local id started ended deadline reason restoration battery_start battery_end power_start power_end extra count=0 scanned=0
  while [ "$scanned" -lt "$HISTORY_MAX_SCAN_ROWS" ] &&
    IFS=$'\t' read -r id started ended deadline reason restoration battery_start battery_end power_start power_end extra; do
    scanned=$((scanned + 1))
    [ "$count" -lt "$HISTORY_MAX_RECORDS" ] || break
    [ -z "${extra:-}" ] || continue
    history_record_valid "$id" "$started" "$ended" "$deadline" "$reason" "$restoration" \
      "$battery_start" "$battery_end" "$power_start" "$power_end" || continue
    printf '%s  %s  %s  %s\n' "$id" "$restoration" "$reason" "$ended"
    count=$((count + 1))
  done < "$HISTORY_FILE"
  [ "$count" -gt 0 ] || echo "No session history."
}
