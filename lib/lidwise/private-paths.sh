#!/bin/bash
# Shared ownership checks; each caller chooses its permitted directory modes.
path_uid() { stat -f %u "$1" 2>/dev/null || stat -c %u "$1" 2>/dev/null; }
path_mode() { stat -f %Lp "$1" 2>/dev/null || stat -c %a "$1" 2>/dev/null; }
path_inode() { stat -f %i "$1" 2>/dev/null || stat -c %i "$1" 2>/dev/null; }

owned_dir_valid() {
  local dir=$1 expected_owner=$2 mode allowed
  shift 2
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  # One stat for owner and mode: this check runs on every state read.
  mode=$(stat -f '%u %Lp' "$dir" 2>/dev/null || stat -c '%u %a' "$dir" 2>/dev/null) || return 1
  [ "${mode%% *}" = "$expected_owner" ] || return 1
  mode=${mode##* }
  for allowed in "$@"; do [ "$mode" != "$allowed" ] || return 0; done
  return 1
}
