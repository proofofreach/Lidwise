#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "$SCRIPT_DIR/../VERSION" ]; then
  ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
else
  ROOT="$SCRIPT_DIR"
fi
APP_NAME="Lidwise.app"
SOURCE_APP="$ROOT/dist/$APP_NAME"
[ -d "$SOURCE_APP" ] || SOURCE_APP="$ROOT/$APP_NAME"

with_sudoers=1
if [ "${1:-}" = "--without-sudoers" ]; then
  with_sudoers=0
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--without-sudoers]" >&2
  exit 2
fi

if [ ! -d "$SOURCE_APP" ]; then
  if [ -x "$ROOT/scripts/build.sh" ]; then
    "$ROOT/scripts/build.sh"
    SOURCE_APP="$ROOT/dist/$APP_NAME"
  else
    echo "Missing $APP_NAME" >&2
    exit 1
  fi
fi

DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$APP_NAME"
BIN_DIR="$HOME/.local/bin"
WRAPPER="$BIN_DIR/lidwise"
LOGIN_PLIST="$HOME/Library/LaunchAgents/com.proofofreach.Lidwise.plist"

if [ -x "$WRAPPER" ] && "$WRAPPER" status 2>/dev/null | grep -q '^AWAKE MODE: ON'; then
  echo "Awake mode is on. Turn it off before upgrading:" >&2
  echo "  lidwise off" >&2
  exit 1
fi

# Names used before the rename to Lidwise (v1.0.0 and earlier).
LEGACY_APP="$DEST_DIR/Closed-Lid Awake.app"
LEGACY_WRAPPER="$BIN_DIR/vibecaf"
LEGACY_LABEL="app.closedlidawake.ClosedLidAwake"
LEGACY_PLIST="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
LEGACY_RULE="/etc/sudoers.d/closed-lid-awake-$(id -un)"

if [ -x "$LEGACY_WRAPPER" ] && "$LEGACY_WRAPPER" status 2>/dev/null | grep -q '^AWAKE MODE: ON'; then
  echo "Awake mode is on. Turn it off before upgrading:" >&2
  echo "  vibecaf off" >&2
  exit 1
fi

mkdir -p "$DEST_DIR" "$BIN_DIR"
rm -rf "$DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

printf '#!/bin/bash\nexec %q "$@"\n' \
  "$DEST_APP/Contents/Resources/lidwise" > "$WRAPPER"
chmod 0755 "$WRAPPER"

# Remove the pre-rename login item, app, and command. The old login item
# points into the old bundle, so it must not survive the upgrade.
if [ -f "$LEGACY_PLIST" ]; then
  /bin/launchctl bootout "gui/$(id -u)/$LEGACY_LABEL" 2>/dev/null || true
  rm -f "$LEGACY_PLIST"
fi
rm -f "$LEGACY_WRAPPER"
rm -rf "$LEGACY_APP"

# An old login item points into the replaced bundle. Reload it if present.
if [ -f "$LOGIN_PLIST" ]; then
  uid=$(id -u)
  /bin/launchctl bootout "gui/$uid/com.proofofreach.Lidwise" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/$uid" "$LOGIN_PLIST"
fi

# The old sudoers rule grants passwordless pmset. Remove it even with
# --without-sudoers, so the upgrade never leaves it behind.
if [ -e "$LEGACY_RULE" ]; then
  sudo rm -f "$LEGACY_RULE"
fi

if [ "$with_sudoers" -eq 1 ]; then
  account=$(id -un)
  case "$account" in
    *[!A-Za-z0-9._-]*)
      echo "Unsupported account name for sudoers: $account" >&2
      exit 1
      ;;
  esac
  rule=$(mktemp "${TMPDIR:-/tmp}/lidwise-sudoers.XXXXXX")
  trap 'rm -f "$rule"' EXIT
  printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' \
    "$account" > "$rule"
  chmod 0440 "$rule"
  sudo /usr/sbin/visudo -cf "$rule"
  sudo /usr/bin/install -o root -g wheel -m 0440 "$rule" \
    "/etc/sudoers.d/lidwise-$account"
fi

echo "Installed $DEST_APP"
echo "Open it from ~/Applications, or run: $WRAPPER status"
if [ "$with_sudoers" -eq 0 ]; then
  echo "Warning: the unattended battery and time guard cannot disable sleep without the sudoers rule."
fi
