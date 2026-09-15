// AppKit views only. Never instantiate AppDelegate or invoke the real helper.
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
assert(featureDelegate.extendItem.keyEquivalent == "e", "Add 30 minutes lacks a keyboard equivalent")
assert(featureDelegate.extendRow.title == "Add 30 minutes", "Extension accessibility label is not action-specific")

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
