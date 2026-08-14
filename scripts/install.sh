#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "$SCRIPT_DIR/../VERSION" ]; then
  ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
else
  ROOT="$SCRIPT_DIR"
fi
APP_NAME="Closed-Lid Awake.app"
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
WRAPPER="$BIN_DIR/vibecaf"
LOGIN_PLIST="$HOME/Library/LaunchAgents/app.closedlidawake.ClosedLidAwake.plist"
GUARDIAN_LABEL="app.closedlidawake.guardian"
GUARDIAN_PLIST="$HOME/Library/LaunchAgents/$GUARDIAN_LABEL.plist"

if [ -x "$WRAPPER" ] && "$WRAPPER" status 2>/dev/null | grep -q '^AWAKE MODE: ON'; then
  echo "Awake mode is on. Turn it off before upgrading:" >&2
  echo "  vibecaf off" >&2
  exit 1
fi

mkdir -p "$DEST_DIR" "$BIN_DIR"
rm -rf "$DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"

printf '#!/bin/bash\nexec %q "$@"\n' \
  "$DEST_APP/Contents/Resources/vibecaf" > "$WRAPPER"
chmod 0755 "$WRAPPER"

# An old login item points into the replaced bundle. Reload it if present.
if [ -f "$LOGIN_PLIST" ]; then
  uid=$(id -u)
  /bin/launchctl bootout "gui/$uid/app.closedlidawake.ClosedLidAwake" 2>/dev/null || true
  /bin/launchctl bootstrap "gui/$uid" "$LOGIN_PLIST"
fi

if [ "$with_sudoers" -eq 1 ]; then
  account=$(id -un)
  case "$account" in
    *[!A-Za-z0-9._-]*)
      echo "Unsupported account name for sudoers: $account" >&2
      exit 1
      ;;
  esac
  rule=$(mktemp "${TMPDIR:-/tmp}/closed-lid-awake-sudoers.XXXXXX")
  trap 'rm -f "$rule"' EXIT
  printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' \
    "$account" > "$rule"
  chmod 0440 "$rule"
  sudo /usr/sbin/visudo -cf "$rule"
  sudo /usr/bin/install -o root -g wheel -m 0440 "$rule" \
    "/etc/sudoers.d/closed-lid-awake-$account"
fi

mkdir -p "$HOME/Library/Logs"
/bin/launchctl bootout "gui/$(id -u)/$GUARDIAN_LABEL" 2>/dev/null || true
"$ROOT/scripts/write-guardian-plist.sh" \
  "$GUARDIAN_PLIST" "$DEST_APP/Contents/Resources/vibecaf"
/bin/launchctl bootstrap "gui/$(id -u)" "$GUARDIAN_PLIST"

echo "Installed $DEST_APP"
echo "Open it from ~/Applications, or run: $WRAPPER status"
if [ "$with_sudoers" -eq 0 ]; then
  echo "Warning: unattended safety recovery cannot disable sleep without the sudoers rule."
fi
