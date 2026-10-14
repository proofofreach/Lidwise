// AppKit integration fixtures. Never launch the app lifecycle or invoke the real helper.
let layoutTestApp = NSApplication.shared
let layoutModel = WorkWindowCardModel(state: State(phase: .off))
let layoutHost = ResizingCardHost(rootView: WorkWindowCard(model: layoutModel,
    onToggle: {}, onDurationChange: { _ in }, onCheckSetup: {}))
layoutHost.observe(layoutModel)
let layoutMenu = NSMenu()
let layoutItem = NSMenuItem()
layoutHost.frame = NSRect(origin: .zero, size: layoutHost.fittingSize)
layoutItem.view = layoutHost
layoutMenu.addItem(layoutItem)
let initialHeight = layoutHost.frame.height
layoutModel.state = State(phase: .unknown, issues: [String(repeating: "Recovery unavailable. ", count: 20)])
RunLoop.current.run(until: Date().addingTimeInterval(0.25))
assert(layoutHost.frame.height > initialHeight, "Long error did not grow the existing menu host")
assert(abs(layoutHost.frame.height - layoutHost.fittingSize.height) < 1, "Error text would be clipped by the old frame")
layoutModel.state = State(phase: .off)
RunLoop.current.run(until: Date().addingTimeInterval(0.25))
assert(abs(layoutHost.frame.height - initialHeight) < 1, "Host did not shrink after error cleared")
var accessibilityPresses = 0
let actionModel = PanelRowModel(symbol: "gear", title: "Test action")
let actionView = PanelRowHostView(model: actionModel, onClick: { accessibilityPresses += 1 })
assert(actionView.accessibilityPerformPress() && accessibilityPresses == 1, "Accessibility press did not activate row")
actionModel.enabled = false
assert(!actionView.accessibilityPerformPress() && accessibilityPresses == 1, "Disabled accessibility action was invoked")

let featureDelegate = AppDelegate()
assert(featureDelegate.action(.extend).item.keyEquivalent == "e", "Add 30 minutes lacks a keyboard equivalent")
assert(featureDelegate.action(.extend).model.title == "Add 30 minutes", "Extension accessibility label is not action-specific")

let verificationModel = GuidedVerificationViewModel()
verificationModel.result = VerificationPayload(
    schemaVersion: 1, expectation: .awake, result: .inconclusive,
    summary: String(repeating: "More closed-lid evidence is needed. ", count: 12),
    durationSeconds: 60, closedLidSeconds: 2, sleepSeconds: 0, maxSampleGap: 1,
    model: "Fixture Mac", osVersion: "Fixture macOS"
)
let verificationHost = NSHostingView(rootView: GuidedVerificationView(
    model: verificationModel, start: {}, close: {}
))
verificationHost.frame = NSRect(origin: .zero, size: verificationHost.fittingSize)
verificationHost.layoutSubtreeIfNeeded()
assert(verificationHost.frame.width >= 480 && verificationHost.frame.height >= 390,
       "Guided verification does not preserve its readable minimum layout")
assert(verificationHost.frame.width < 700, "Long verification output widened the utility window")

let hookModel = AgentIntegrationViewModel()
hookModel.status = HookStatusPayload(
    schemaVersion: 1,
    claude: HookProviderStatus(supported: true, configured: false,
                               events: ["working", "waiting", "finished", "failed"], reason: nil),
    codex: HookProviderStatus(supported: false, configured: false, events: [],
                              reason: "No supported lifecycle hook configuration was found.")
)
let hookHost = NSHostingView(rootView: AgentIntegrationView(
    model: hookModel, refresh: {}, preview: {}, configure: { _ in }, close: {}
))
hookHost.frame = NSRect(origin: .zero, size: hookHost.fittingSize)
hookHost.layoutSubtreeIfNeeded()
assert(hookHost.frame.width >= 520 && hookHost.frame.width < 700,
       "Integration status does not fit its bounded utility window")

print("dynamic sizing, feature layouts, keyboard, and accessibility actions: PASS")

// Failures: UI rendering launches work; recovery adds a second timer; persistent
// faults poll forever; command failure stops refreshes; native/hosted rows drift.
featureDelegate.state = State(phase: .ownedOn, sessionID: "readiness-fixture", recoveryReady: false)
featureDelegate.scheduleRefresh()
assert(featureDelegate.timer != nil && featureDelegate.timer!.fireDate.timeIntervalSinceNow <= 1.1)
let firstTimer = featureDelegate.timer!
featureDelegate.scheduleRefresh()
assert(!firstTimer.isValid && featureDelegate.timer!.isValid)
let renderTimer = featureDelegate.timer
featureDelegate.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
featureDelegate.applyState()
assert(featureDelegate.timer === renderTimer, "Rendering changed the refresh schedule")
featureDelegate.state.recoveryReady = true
featureDelegate.scheduleRefresh()
assert(featureDelegate.timer!.fireDate.timeIntervalSinceNow > 50)
featureDelegate.state.recoveryReady = false
featureDelegate.readinessDeadline = Date().addingTimeInterval(-1)
featureDelegate.scheduleRefresh()
assert(featureDelegate.timer!.fireDate.timeIntervalSinceNow > 50)
featureDelegate.state.pending = .saving
featureDelegate.scheduleRefresh()
assert(featureDelegate.timer == nil)
featureDelegate.state = State(phase: .off)
featureDelegate.scheduleRefresh()
assert(featureDelegate.readinessSessionID == nil)
assert(featureDelegate.timer!.fireDate.timeIntervalSinceNow > 50)
featureDelegate.timer?.invalidate()

// Action metadata owns native accessibility/keyboard state and hosted rows.
featureDelegate.installActionRows()
featureDelegate.state = State(phase: .off)
featureDelegate.applyState()
for action in featureDelegate.menuActions {
    assert(action.item.title == action.model.title)
    assert(action.item.isEnabled == action.model.enabled)
    assert(action.item.state == (action.model.checked == true ? .on : .off))
}
let recoveryAction = featureDelegate.action(.recovery)
assert(recoveryAction.group == .session)
featureDelegate.setDrawer(expanded: true)
assert(!recoveryAction.item.isHidden)
featureDelegate.setDrawer(expanded: false)
assert(recoveryAction.item.isHidden)
assert(featureDelegate.action(.extend).item.keyEquivalent == "e")
assert(!featureDelegate.action(.turnOffQuit).item.isEnabled)
assert(!featureDelegate.action(.requireAC).model.enabled)
NSStatusBar.system.removeStatusItem(featureDelegate.item)
print("Single refresh timer, pure rendering, and unified action metadata: PASS")

// Exercise the command/reconcile path with a recording helper boundary.
final class LayoutCommandRunner: CommandRunning {
    let lock = NSLock()
    var calls: [([String], TimeInterval)] = []
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        lock.lock(); calls.append((arguments, timeout)); lock.unlock()
        return CommandResult(stdout: Data(), stderr: Data("fixture failure".utf8),
                             exitCode: 1, timedOut: false, launchError: nil)
    }
}
let commandRunner = LayoutCommandRunner()
let commandDelegate = AppDelegate(runner: commandRunner)
commandDelegate.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
commandDelegate.performSetting(arguments: ["config", "set", "duration", "1800"], verify: { _ in true })
let settingDeadline = Date().addingTimeInterval(3)
while commandDelegate.state.pending != nil && Date() < settingDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
assert(commandDelegate.state.pending == nil && commandDelegate.state.commandError != nil)
assert(commandDelegate.hud == nil && commandDelegate.timer != nil)
assert(commandRunner.calls.count == 2 && commandRunner.calls[0].1 == 10 && commandRunner.calls[1].1 == 5)
commandDelegate.performMutation(arguments: ["off"], pending: .turningOff, expected: .off)
let mutationDeadline = Date().addingTimeInterval(3)
while commandDelegate.state.pending != nil && Date() < mutationDeadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
assert(commandDelegate.state.pending == nil && commandDelegate.hud != nil)
assert(commandDelegate.timer != nil && commandRunner.calls.count == 4 && commandRunner.calls[2].1 == 30)
commandDelegate.hud?.orderOut(nil)
commandDelegate.refresh(includeActivity: false)
_ = commandDelegate.revisionGate.issue() // A discarded observation must not stop future ticks.
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
assert(commandDelegate.timer?.isValid == true)
commandDelegate.timer?.invalidate()
NSStatusBar.system.removeStatusItem(commandDelegate.item)
print("Command timeouts, feedback, failure and stale-refresh liveness: PASS")
