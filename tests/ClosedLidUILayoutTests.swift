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
print("dynamic menu card sizing and accessibility action: PASS")
