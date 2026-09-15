#!/bin/bash
# Entire installation target, privilege layer and launchd are isolated fixtures.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/closedlid-lifecycle.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export CLA_INSTALL_HOME="$WORK/home" CLA_DAEMON_DIR="$WORK/daemons" CLA_SUDOERS_DIR="$WORK/rules"
export CLA_SOURCE_APP="$WORK/source.app" CLA_SUDO="$WORK/sudo" CLA_LAUNCHCTL="$WORK/launchctl" CLA_PMSET="$WORK/pmset"
export FIXTURE="$WORK"
mkdir -p "$CLA_SOURCE_APP/Contents/"{MacOS,Resources/lib/vibecaf,Helpers} "$CLA_DAEMON_DIR" "$CLA_SUDOERS_DIR" "$WORK/jobs"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/MacOS/ClosedLidAwake"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-thermal"
cp /usr/bin/true "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-agent-scan-core"
cat > "$CLA_SOURCE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ClosedLidAwake</string><key>CFBundleIdentifier</key><string>app.closedlidawake.fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$CLA_SOURCE_APP/Contents/Resources/vibecaf" <<'HELPER'
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
esac
HELPER
cp "$CLA_SOURCE_APP/Contents/Resources/vibecaf" "$CLA_SOURCE_APP/Contents/Resources/vibecaf-agent-scan"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/vibecaf/network.sh"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/vibecaf/session.sh"
echo '# module' > "$CLA_SOURCE_APP/Contents/Resources/lib/vibecaf/observation.sh"
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
chmod +x "$WORK/"{sudo,launchctl,pmset} "$CLA_SOURCE_APP/Contents/Resources/"vibecaf*
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-thermal" 2>/dev/null
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-agent-scan-core" 2>/dev/null
/usr/bin/codesign --force --sign - "$CLA_SOURCE_APP" 2>/dev/null
echo off > "$WORK/phase"
printf '%s ALL=(root) NOPASSWD: /usr/sbin/ipconfig set en0 DHCP\n' "$(id -un)" > "$CLA_SUDOERS_DIR/vibecaf-ipconfig"
"$ROOT/scripts/install.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$CLA_SUDOERS_DIR/vibecaf-ipconfig" ]
APP="$CLA_INSTALL_HOME/Applications/Closed-Lid Awake.app"
WRAPPER="$CLA_INSTALL_HOME/.local/bin/vibecaf"
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
mv "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-agent-scan-core" "$WORK/scanner"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
grep -q 'Incomplete app: Contents/Helpers/vibecaf-agent-scan-core' "$WORK/output"
[ -f "$APP/prior-marker" ]
mv "$WORK/scanner" "$CLA_SOURCE_APP/Contents/Helpers/vibecaf-agent-scan-core"
# If restoration itself fails, retain backups and report the incomplete rollback.
touch "$WORK/bootstrap-always-fails"
if "$ROOT/scripts/install.sh" > "$WORK/output" 2>&1; then exit 1; fi
grep -q 'Rollback was incomplete' "$WORK/output"
compgen -G "$CLA_INSTALL_HOME/Applications/.closedlid-install.*" >/dev/null
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
printf '%s ALL=(root) NOPASSWD: /usr/sbin/ipconfig set en0 DHCP\n' "$(id -un)" > "$CLA_SUDOERS_DIR/vibecaf-ipconfig"
"$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ ! -e "$APP" ] && [ "$(cat "$WORK/phase")" = off ]
[ ! -e "$CLA_SUDOERS_DIR/vibecaf-ipconfig" ]
# Removing this app leaves a known external hold unchanged.
echo off > "$WORK/phase"
"$ROOT/scripts/install.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
echo external-on > "$WORK/phase"
"$ROOT/scripts/uninstall.sh" > "$WORK/output" 2>&1 || { cat "$WORK/output"; exit 1; }
[ "$(cat "$WORK/phase")" = external-on ] && [ ! -e "$APP" ]
echo 'install staging, auth/copy failure, rollback/retained backup, required helper, state refusal, partial/external uninstall: ok' 
