#!/bin/bash
# Failures: undeletable/unsafe wakes spin; a wake during checking is lost;
# heartbeat waits ignore session replacement or never stop; cleanup removes
# unknown files; a shared ownership check weakens the session's 700 rule.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-readiness.XXXXXX")
trap 'chmod -R u+w "$WORK"; rm -rf "$WORK"' EXIT
USER_ID=$(id -u)
SESSION_DIR="$WORK/session"; GUARDIAN_EVERY=4
source "$ROOT/lib/lidwise/session.sh"
source "$ROOT/lib/lidwise/guardian.sh"
mkdir -m 700 "$SESSION_DIR"

# Exercise production loop ordering with a deterministic clock. No power calls.
for scenario in normal pending during-check bad-mode failed-remove; do
  (
    checks=0; elapsed=0
    guardian_check_once() {
      checks=$((checks + 1))
      if [ "$checks" -eq 2 ]; then
        case "$scenario" in
          normal|pending|bad-mode|failed-remove) [ "$elapsed" -eq 4 ] ;;
          during-check) [ "$elapsed" -eq 0 ] ;;
        esac || { echo "FAIL: $scenario cadence ($elapsed seconds)"; exit 1; }
        exit 0
      fi
      [ "$scenario" != during-check ] || printf 'new-session\n' > "$SESSION_DIR/guardian_wake"
      return 0
    }
    sleep() { elapsed=$((elapsed + $1)); }
    case "$scenario" in
      pending|failed-remove) printf 'pending\n' > "$SESSION_DIR/guardian_wake" ;;
      bad-mode) printf 'pending\n' > "$SESSION_DIR/guardian_wake"; chmod 755 "$SESSION_DIR" ;;
    esac
    if [ "$scenario" = failed-remove ]; then rm() { return 1; }; fi
    guardian_loop
  )
  chmod 700 "$SESSION_DIR"; rm -f "$SESSION_DIR/guardian_wake"
done
echo 'PASS: guardian wake and failed removal preserve bounded cadence'

# An acknowledgement belongs to one current session and must be fresh.
write_field "$SESSION_DIR" id fixture
write_field "$SESSION_DIR" guardian_session fixture
write_field "$SESSION_DIR" guardian_heartbeat "$(date +%s)"
guardian_wait_for_session fixture 1
write_field "$SESSION_DIR" guardian_session stale
if guardian_wait_for_session fixture 1; then echo 'FAIL: accepted another session'; exit 1; fi
write_field "$SESSION_DIR" guardian_session fixture
write_field "$SESSION_DIR" guardian_heartbeat 1
if guardian_wait_for_session fixture 1; then echo 'FAIL: accepted stale heartbeat'; exit 1; fi
(
  slept=0
  sleep() { slept=$((slept + 1)); write_field "$SESSION_DIR" id replacement; }
  guardian_wait_for_session fixture 3 && exit 1
  [ "$slept" -eq 1 ]
)
echo 'PASS: bounded guardian acknowledgement validates identity and freshness'

# One allowlist controls writes and cleanup; unknown files/links survive.
for field in "${SESSION_FIELDS[@]}"; do write_field "$SESSION_DIR" "$field" fixture; done
printf 'keep\n' > "$WORK/target"
ln -s "$WORK/target" "$SESSION_DIR/unexpected-link"
printf 'keep\n' > "$SESSION_DIR/unexpected"
if write_field "$SESSION_DIR" typo_field fixture; then echo 'FAIL: unknown session field accepted'; exit 1; fi
session_clear
for field in "${SESSION_FIELDS[@]}"; do [ ! -e "$SESSION_DIR/$field" ]; done
[ -L "$SESSION_DIR/unexpected-link" ] && [ -f "$SESSION_DIR/unexpected" ]
[ "$(cat "$WORK/target")" = keep ]

source "$ROOT/lib/lidwise/observation.sh"
private_dir_valid "$SESSION_DIR"
owned_dir_valid "$SESSION_DIR" "$USER_ID" 700 500
chmod 500 "$SESSION_DIR"
if private_dir_valid "$SESSION_DIR"; then echo 'FAIL: session accepted mode 500'; exit 1; fi
owned_dir_valid "$SESSION_DIR" "$USER_ID" 700 500
chmod 755 "$SESSION_DIR"
if owned_dir_valid "$SESSION_DIR" "$USER_ID" 700 500; then exit 1; fi
chmod 700 "$SESSION_DIR"
ln -s "$SESSION_DIR" "$WORK/linked-directory"
if owned_dir_valid "$WORK/linked-directory" "$USER_ID" 700 500; then exit 1; fi
if owned_dir_valid "$SESSION_DIR" "$((USER_ID + 1))" 700 500; then exit 1; fi
printf 'cache\n' > "$WORK/cache"; chmod 600 "$WORK/cache"
agent_private_file "$WORK/cache"
dd if=/dev/zero of="$WORK/cache" bs=262145 count=1 2>/dev/null
if agent_private_file "$WORK/cache"; then echo 'FAIL: lost cache size limit'; exit 1; fi
echo 'PASS: session allowlist and distinct directory/file policies'
