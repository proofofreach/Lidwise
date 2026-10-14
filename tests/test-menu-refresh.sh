#!/bin/bash
# End-to-end AppDelegate -> ProcessRunner -> isolated CLI -> state/timer checks.
# Failures: post-on status failure waits a minute; errors reset burst deadlines;
# opening the menu during a mutation loses its queued network observation.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/lidwise-menu-refresh.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
APP="$OUT/RefreshProbe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.lidwise.tests.refresh</string><key>CFBundleExecutable</key><string>RefreshProbe</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$APP/Contents/Resources/lidwise" <<'CLI'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$LIDWISE_QA_DIR/calls"
case "$1" in
  on) touch "$LIDWISE_QA_DIR/fail-next" ;;
  config) sleep 0.7 ;;
  status)
    if [ -f "$LIDWISE_QA_DIR/slow-next" ]; then
      rm "$LIDWISE_QA_DIR/slow-next"; touch "$LIDWISE_QA_DIR/slow-started"; sleep 0.4
    fi
    if [ -f "$LIDWISE_QA_DIR/fail-next" ]; then rm "$LIDWISE_QA_DIR/fail-next"; exit 1; fi
    cat "$LIDWISE_QA_DIR/status.json" ;;
  *) exit 2 ;;
esac
CLI
chmod 755 "$APP/Contents/Resources/lidwise"
cat > "$OUT/status.json" <<'JSON'
{"schema_version":1,"phase":"owned-on","session_id":"fixture","started_at":1,"deadline":9999999999,"remaining_seconds":100,"duration_seconds":21600,"battery_floor":20,"power_source":"AC","battery_percent":100,"thermal":"nominal","guard_running":true,"guardian_running":true,"recovery_ready":true,"issues":[],"network_state":"online","network_detail":"online","network_recovery":true,"agent_notifications":false,"agents":{"claude":{"working":0,"waiting":0,"quiet":0,"finished":0,"failed":0},"codex":{"working":0,"waiting":0,"quiet":0,"finished":0,"failed":0}},"goals":{"active":0,"stalled":0,"completed":0,"failed":0},"observed_at":1}
JSON
sed '/^#if CARD_PREVIEW/,$d' "$ROOT/src/Lidwise.swift" > "$OUT/main.swift"
cat >> "$OUT/main.swift" <<'SWIFT'
let testApp = NSApplication.shared
let directory = ProcessInfo.processInfo.environment["LIDWISE_QA_DIR"]!
assert(lidwisePath.hasPrefix(directory), "Fixture must never invoke the installed helper")
let subject = AppDelegate()
subject.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
func awaitState(_ description: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    assert(condition(), description)
}
func flag(_ name: String) { FileManager.default.createFile(atPath: directory + "/" + name, contents: Data()) }
subject.state = State(phase: .off)
subject.performMutation(arguments: ["on"], pending: .turningOn, expected: .ownedOn)
awaitState("activation completes", { subject.state.pending == nil })
assert(subject.state.phase == .unknown && subject.readinessDeadline != nil)
let activationDeadline = subject.readinessDeadline
assert(subject.timer!.fireDate.timeIntervalSinceNow <= 1.1)
awaitState("timer observes post-activation readiness", { subject.state.recoveryReady })
assert(subject.readinessSessionID == "fixture" && subject.readinessDeadline == activationDeadline)
assert(subject.timer!.fireDate.timeIntervalSinceNow > 50)
subject.hud?.orderOut(nil)
subject.state.recoveryReady = false
subject.scheduleRefresh()
let retryDeadline = subject.readinessDeadline
flag("fail-next")
subject.refresh(includeActivity: false)
awaitState("failed observation finishes", { !subject.refreshInFlight })
assert(subject.state.phase == .unknown && subject.readinessDeadline == retryDeadline)
assert(subject.timer!.fireDate.timeIntervalSinceNow <= 1.1)
awaitState("timer recovers from transient status failure", { subject.state.recoveryReady })
assert(subject.readinessDeadline == retryDeadline)

flag("slow-next")
subject.refresh(includeActivity: false)
awaitState("old observation starts", { FileManager.default.fileExists(atPath: directory + "/slow-started") })
subject.refresh(probeNet: true, includeActivity: false)
subject.performSetting(arguments: ["config", "set", "duration", "1800"], verify: { _ in true })
awaitState("queued network observation survives stale result and mutation", {
    (try? String(contentsOfFile: directory + "/calls").contains("status --json --net")) == true
})
awaitState("observations finish", { !subject.refreshInFlight && subject.state.pending == nil })
subject.timer?.invalidate()
NSStatusBar.system.removeStatusItem(subject.item)
print("PASS: real helper processes preserve activation retries, bounded deadlines and queued menu probes")
SWIFT
xcrun swiftc -target "$(uname -m)-apple-macosx13.0" -framework AppKit -framework Carbon \
  "$OUT/main.swift" "$ROOT/src/ProcessRunner.swift" "$ROOT/src/LidwiseUIModel.swift" \
  "$ROOT/src/LidwiseFeatureUI.swift" -o "$APP/Contents/MacOS/RefreshProbe"
LIDWISE_QA_DIR="$OUT" "$APP/Contents/MacOS/RefreshProbe"
# Retain a verifiable artifact; the script recreates its fixture on every run.
mkdir -p "$ROOT/.build/verification/report-fixes"
cp "$OUT/calls" "$ROOT/.build/verification/report-fixes/menu-refresh-calls.txt"
