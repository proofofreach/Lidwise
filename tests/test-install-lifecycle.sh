#!/bin/bash
# Entire installation target, privilege layer and launchd are isolated fixtures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-lifecycle.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export CLA_INSTALL_HOME="$WORK/home" CLA_DAEMON_DIR="$WORK/daemons" CLA_SUDOERS_DIR="$WORK/rules"
export CLA_SOURCE_APP="$WORK/source.app" CLA_SUDO="$WORK/sudo" CLA_LAUNCHCTL="$WORK/launchctl" CLA_PMSET="$WORK/pmset"
export FIXTURE="$WORK"
mkdir -p "$CLA_SOURCE_APP/Contents/"{MacOS,Resources/lib/lidwise,Helpers} "$CLA_DAEMON_DIR" "$CLA_SUDOERS_DIR" "$WORK/jobs"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/MacOS/Lidwise"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/Helpers/lidwise-thermal"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/Helpers/lidwise-agent-scan-core"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/Helpers/lidwise-lid-probe"
cat > "$CLA_SOURCE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Lidwise</string><key>CFBundleIdentifier</key><string>app.lidwiseawake.fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$CLA_SOURCE_APP/Contents/Resources/lidwise" <<'HELPER'
#!/bin/bash
case "$1" in
 __maintenance)
   shift
   if [ "${1:-}" = --remove ]; then
     shift
     if [ "$(cat "$FIXTURE/phase")" = owned-on ]; then
       [ ! -e "$FIXTURE/off-fails" ] || exit 1
       echo off > "$FIXTURE/phase"
     fi
   else
     [ "$(cat "$FIXTURE/phase")" = off ] || exit 1
   fi
   shift; exec "$@" ;;
 status) printf '{"phase":"%s"}\n' "$(cat "$FIXTURE/phase")" ;;
 off) [ ! -e "$FIXTURE/off-fails" ] || exit 1; echo off > "$FIXTURE/phase" ;;
 hooks)
   [ "$2 $3" = 'remove all' ] || exit 2
   [ ! -e "$FIXTURE/hooks-fail" ] || exit 1
   touch "$FIXTURE/hooks-removed" ;;
esac
HELPER
cp "$CLA_SOURCE_APP/Contents/Resources/lidwise" "$CLA_SOURCE_APP/Contents/Resources/lidwise-agent-scan"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/network.sh"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/session.sh"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/observation.sh"
for module in history guardian private-paths; do echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/$module.sh"; done
cat > "$CLA_SUDO" <<'SUDO'
#!/bin/bash
set -e
[ ! -e "$FIXTURE/auth-fails" ] || exit 1
case "$1" in
 -v) exit 0 ;;
 /usr/sbin/visudo) exit 0 ;;
 /usr/bin/install) shift; shift 4; exec /usr/bin/install "$@" ;;
 *) exec "$@" ;;
esac
SUDO
cat > "$CLA_LAUNCHCTL" <<'LAUNCH'
#!/bin/bash
set -e
case "$1" in
 print) [ -f "$FIXTURE/jobs/${2##*/}" ] ;;
 bootout) rm -f "$FIXTURE/jobs/${2##*/}" ;;
 bootstrap)
   [ ! -e "$FIXTURE/bootstrap-always-fails" ] || exit 1
   if [ -e "$FIXTURE/bootstrap-fails" ]; then rm "$FIXTURE/bootstrap-fails"; exit 1; fi
   label=$(/usr/bin/plutil -extract Label raw -o - "$3")
   touch "$FIXTURE/jobs/$label" ;;
esac
LAUNCH
cat > "$CLA_PMSET" <<'PMSET'
#!/bin/bash
echo ' SleepDisabled 0'
PMSET
chmod +x "$WORK/"{sudo,launchctl,pmset} "$CLA_SOURCE_APP/Contents/Resources/"lidwise*
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP/Contents/Helpers/lidwise-thermal" 2>/dev/null
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP/Contents/Helpers/lidwise-agent-scan-core" 2>/dev/null
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP/Contents/Helpers/lidwise-lid-probe" 2>/dev/null
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP" 2>/dev/null
echo off > "$WORK/phase"
printf '%s ALL=(root) NOPASSWD: /usr/sbin/ipconfig set en0 DHCP\n' "$(id -un)" > "$CLA_SUDOERS_DIR/vibecaf-ipconfig"
"$ROOT/scripts/install.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$CLA_SUDOERS_DIR/vibecaf-ipconfig" ]
APP="$CLA_INSTALL_HOME/Applications/Lidwise.app"
WRAPPER="$CLA_INSTALL_HOME/.local/bin/lidwise"
[ -x "$WRAPPER" ] && [ -e "$WORK/jobs/app.closedlidawake.guardian.$(id -u)" ]
# Canceled auth occurs before replacing the prior app or changing jobs.
echo previous > "$APP/prior-marker"
touch "$WORK/auth-fails"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then echo 'accepted canceled auth'; exit 1; fi
[ -f "$APP/prior-marker" ]; rm "$WORK/auth-fails"
# A failed replacement bootstrap restores prior files and loaded guardian.
touch "$WORK/bootstrap-fails"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then echo 'accepted failed bootstrap'; exit 1; fi
[ -f "$APP/prior-marker" ] && [ -x "$WRAPPER" ] && [ -f "$WORK/jobs/app.closedlidawake.guardian.$(id -u)" ]
# Copy failure never removes the prior app.
printf '#!/bin/bash\nexit 22\n' > "$WORK/bad-copy"
chmod +x "$WORK/bad-copy"
if CLA_DITTO="$WORK/bad-copy" "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
[ -f "$APP/prior-marker" ]
# A missing required scanner is rejected before replacement.
mv "$CLA_SOURCE_APP/Contents/Helpers/lidwise-agent-scan-core" "$WORK/scanner"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
grep -q 'Incomplete app: Contents/Helpers/lidwise-agent-scan-core' "$WORK/output"
[ -f "$APP/prior-marker" ]
mv "$WORK/scanner" "$CLA_SOURCE_APP/Contents/Helpers/lidwise-agent-scan-core"
# Every required library is checked before replacing an installed app.
for module in history guardian private-paths; do
  mv "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/$module.sh" "$WORK/$module.sh"
  if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
  grep -q "Missing helper module: $module" "$WORK/output"
  [ -f "$APP/prior-marker" ]
  mv "$WORK/$module.sh" "$CLA_SOURCE_APP/Contents/Resources/lib/lidwise/$module.sh"
done
# If restoration itself fails, retain backups and report the incomplete rollback.
touch "$WORK/bootstrap-always-fails"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
grep -q 'Rollback was incomplete' "$WORK/output"
compgen -G "$CLA_INSTALL_HOME/Applications/.lidwise-install.*" >/dev/null
[ -f "$APP/prior-marker" ]
rm "$WORK/bootstrap-always-fails"
touch "$WORK/jobs/app.closedlidawake.guardian.$(id -u)"
# Unknown and externally owned state both refuse replacement.
for phase in unknown external-on owned-on; do
  echo "$phase" > "$WORK/phase"
  if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then echo "accepted $phase upgrade"; exit 1; fi
  [ -f "$APP/prior-marker" ]
done
# Missing wrapper still restores via the app helper; failed restoration retains it.
rm "$WRAPPER"; echo owned-on > "$WORK/phase"; touch "$WORK/off-fails"
if "$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1; then echo 'removed failed recovery'; exit 1; fi
[ -d "$APP" ] && [ -f "$CLA_SUDOERS_DIR/closed-lid-awake-$(id -un)" ]
rm "$WORK/off-fails"
# A hook-removal error keeps the app and recovery installed after restoring sleep.
touch "$WORK/hooks-fail"
if "$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1; then echo 'removed app with failed hook cleanup'; exit 1; fi
[ -d "$APP" ] && [ -f "$CLA_SUDOERS_DIR/closed-lid-awake-$(id -un)" ]
grep -q 'Could not remove agent hooks' "$WORK/output"
rm "$WORK/hooks-fail"
printf '%s ALL=(root) NOPASSWD: /usr/sbin/ipconfig set en0 DHCP\n' "$(id -un)" > "$CLA_SUDOERS_DIR/vibecaf-ipconfig"
"$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$APP" ] && [ "$(cat "$WORK/phase")" = off ]
[ -e "$WORK/hooks-removed" ]
[ ! -e "$CLA_SUDOERS_DIR/vibecaf-ipconfig" ]
# Removing this app leaves a known external hold unchanged.
echo off > "$WORK/phase"
"$ROOT/scripts/install.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
echo external-on > "$WORK/phase"
"$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ "$(cat "$WORK/phase")" = external-on ] && [ ! -e "$APP" ]
echo 'install staging, auth/copy failure, rollback/retained backup, required helper, state refusal, partial/external uninstall: ok'

# Rename upgrades use the same guardian identity and restore the old app path on failure.
echo off > "$WORK/phase"
OLD_APP="$CLA_INSTALL_HOME/Applications/Closed-Lid Awake.app"
OLD_WRAPPER="$CLA_INSTALL_HOME/.local/bin/vibecaf"
LOGIN="$CLA_INSTALL_HOME/Library/LaunchAgents/app.closedlidawake.ClosedLidAwake.plist"
/usr/bin/ditto "$CLA_SOURCE_APP" "$OLD_APP"
mv "$OLD_APP/Contents/Resources/lidwise" "$OLD_APP/Contents/Resources/vibecaf"
mv "$OLD_APP/Contents/MacOS/Lidwise" "$OLD_APP/Contents/MacOS/ClosedLidAwake"
printf '#!/bin/bash\nexec %q "$@"\n' "$OLD_APP/Contents/Resources/vibecaf" > "$OLD_WRAPPER"
chmod +x "$OLD_WRAPPER"
/usr/bin/plutil -create xml1 "$LOGIN"
/usr/bin/plutil -insert Label -string app.closedlidawake.ClosedLidAwake "$LOGIN"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$LOGIN"
/usr/bin/plutil -insert ProgramArguments.0 -string "$OLD_APP/Contents/MacOS/ClosedLidAwake" "$LOGIN"
cp "$LOGIN" "$WORK/original-login.plist"
cp "$OLD_WRAPPER" "$WORK/original-wrapper"
touch "$WORK/bootstrap-fails"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then echo 'accepted failed rename upgrade'; exit 1; fi
[ -d "$OLD_APP" ] && [ ! -e "$APP" ] && [ ! -e "$WRAPPER" ]
cmp "$LOGIN" "$WORK/original-login.plist"
cmp "$OLD_WRAPPER" "$WORK/original-wrapper"
"$ROOT/scripts/install.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$OLD_APP" ] && [ -d "$APP" ]
cmp "$WRAPPER" "$OLD_WRAPPER"
[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$LOGIN")" = "$APP/Contents/MacOS/Lidwise" ]
"$OLD_WRAPPER" status | grep -q '"phase":"off"'
"$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$OLD_WRAPPER" ] && [ ! -e "$APP" ]
echo 'Lidwise rename upgrade, login migration, compatibility CLI, rollback and removal: ok'
