// Closed-Lid Awake — menu bar control for ~/.local/bin/vibecaf
import AppKit
import Carbon.HIToolbox
import SwiftUI

let bundledVibecafPath = Bundle.main.url(forResource: "vibecaf", withExtension: nil)?.path
let vibecafPath = bundledVibecafPath
    ?? NSString(string: "~/.local/bin/vibecaf").expandingTildeInPath
let agentLabel = Bundle.main.bundleIdentifier ?? "app.closedlidawake.ClosedLidAwake"
let agentPlist = NSString(string: "~/Library/LaunchAgents/\(agentLabel).plist").expandingTildeInPath
let kAutoEnable = "autoEnableAtLogin"

@discardableResult
func vibecaf(_ args: String...) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: vibecafPath)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    guard (try? p.run()) != nil else { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

struct AgentCounts {
    var active = 0
    var idle = 0
    var completed = 0

    var detail: String {
        var parts: [String] = []
        if active > 0 { parts.append("\(active) active") }
        if idle > 0 { parts.append("\(idle) idle") }
        if completed > 0 { parts.append("\(completed) done") }
        return parts.isEmpty ? "Not detected" : parts.joined(separator: " · ")
    }
}

struct State {
    var on = false
    var power = ""
    var onBattery = false
    var net = ""
    var netOK = false
    var carrier = ""
    var watchdog = false
    var guarded = false
    var guardian = ""
    var autoOff = ""
    var floor = ""
    var thermal = ""
    var goals = ""
    var claude = AgentCounts()
    var codex = AgentCounts()
}

func agentCounts(from line: Substring) -> AgentCounts {
    let numbers = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard numbers.count >= 3 else { return AgentCounts() }
    return AgentCounts(active: numbers[0], idle: numbers[1], completed: numbers[2])
}

// `probeNet: false` is the cheap path — pmset and pidfiles only, and the
// network line comes from whatever the watchdog last saw. A live probe costs
// 8.5s on a dead network, so only ask for one when the user is looking.
func readState(probeNet: Bool = false) -> State {
    var s = State()
    let out = probeNet ? vibecaf("status", "--net") : vibecaf("status")
    for line in out.split(separator: "\n") {
        if line.hasPrefix("AWAKE MODE:") { s.on = line.contains("ON") }
        if line.hasPrefix("Power:") {
            s.power = line.replacingOccurrences(of: "Power: ", with: "")
            s.onBattery = line.contains("Battery")
        }
        if line.hasPrefix("Network:") {
            s.net = line.replacingOccurrences(of: "Network: ", with: "")
            s.netOK = line.contains("online")
        }
        if line.hasPrefix("Carrier:") {
            s.carrier = line.replacingOccurrences(of: "Carrier: ", with: "")
        }
        if line.hasPrefix("Wi-Fi watchdog pid:") { s.watchdog = !line.contains("none") }
        if line.hasPrefix("Guard pid:") { s.guarded = !line.contains("none") }
        if line.hasPrefix("Crash guardian:") { s.guardian = line.replacingOccurrences(of: "Crash guardian: ", with: "") }
        if line.hasPrefix("Auto-off in:") { s.autoOff = line.replacingOccurrences(of: "Auto-off in: ", with: "") }
        if line.hasPrefix("Battery floor:") { s.floor = line.replacingOccurrences(of: "Battery floor: ", with: "") }
        if line.hasPrefix("Thermal:") { s.thermal = line.replacingOccurrences(of: "Thermal: ", with: "") }
        if line.hasPrefix("Goals:") { s.goals = line.replacingOccurrences(of: "Goals: ", with: "") }
        if line.hasPrefix("Claude Code:") { s.claude = agentCounts(from: line) }
        if line.hasPrefix("Codex:") { s.codex = agentCounts(from: line) }
    }
    return s
}

// One palette for the whole menu. The card and every action row below it draw
// from these tokens, so the menu reads as a single panel rather than a styled
// card bolted onto a stock NSMenu.
enum Ink {
    static let canvas = Color(red: 0.055, green: 0.067, blue: 0.12)
    static let bay = Color(red: 0.075, green: 0.09, blue: 0.16)
    static let rail = Color(red: 0.065, green: 0.078, blue: 0.135)
    static let line = Color.white.opacity(0.11)
    static let hover = Color.white.opacity(0.07)
    static let primary = Color(red: 0.92, green: 0.94, blue: 1.0)
    static let secondary = Color(red: 0.62, green: 0.66, blue: 0.82)
    static let tertiary = Color(red: 0.62, green: 0.66, blue: 0.82).opacity(0.7)
    static let accent = Color(red: 0.39, green: 0.55, blue: 1.0)
    static let mint = Color(red: 0.39, green: 0.85, blue: 0.69)
    static let amber = Color(red: 0.95, green: 0.69, blue: 0.32)
    static let coral = Color(red: 1.0, green: 0.46, blue: 0.48)

    static let panelWidth: CGFloat = 408
    static let panelRadius: CGFloat = 18
    static let inset: CGFloat = 18
}

// Where a view sits in the stacked panel. The menu is several NSMenuItems, each
// with its own view, so every item paints its own slice of one continuous
// rounded panel: the top slice rounds its upper corners, the bottom slice its
// lower corners, and the middle slices draw only the two vertical edges.
enum PanelSlice {
    case top, middle, bottom, whole

    var roundsTop: Bool { self == .top || self == .whole }
    var roundsBottom: Bool { self == .bottom || self == .whole }
}

private struct PanelSliceBackground: ViewModifier {
    let slice: PanelSlice

    func body(content: Content) -> some View {
        // The rounded rect is pushed past the clip on the sides that must stay
        // open, so clipping leaves only the edges this slice owns — no seams,
        // no per-corner shape maths.
        let bleed = Ink.panelRadius + 2
        content
            .background(
                RoundedRectangle(cornerRadius: Ink.panelRadius)
                    .fill(Ink.canvas)
                    .padding(.top, slice.roundsTop ? 0 : -bleed)
                    .padding(.bottom, slice.roundsBottom ? 0 : -bleed)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ink.panelRadius)
                    .stroke(Ink.line, lineWidth: 1)
                    .padding(.top, slice.roundsTop ? 0 : -bleed)
                    .padding(.bottom, slice.roundsBottom ? 0 : -bleed)
            )
            .clipped()
    }
}

extension View {
    func panelSlice(_ slice: PanelSlice) -> some View { modifier(PanelSliceBackground(slice: slice)) }
}

// State for one action row. Mutated from applyState() so rows update in place
// without rebuilding their hosting views.
final class PanelRowModel: ObservableObject {
    @Published var symbol: String
    @Published var title: String
    @Published var subtitle: String
    @Published var shortcut: String
    @Published var checked: Bool?
    @Published var warning = false
    @Published var highlighted = false
    // nil: plain row. false/true: disclosure row, collapsed/expanded.
    @Published var expanded: Bool?
    let slice: PanelSlice
    // Rows inside the settings drawer sit one step in from the top-level rows.
    let nested: Bool
    // Toggles and the drawer header flip in place; everything else dismisses.
    let closesMenu: Bool

    init(symbol: String, title: String, subtitle: String = "", shortcut: String = "",
         checked: Bool? = nil, expanded: Bool? = nil, slice: PanelSlice = .middle,
         nested: Bool = false, closesMenu: Bool = true) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.checked = checked
        self.expanded = expanded
        self.slice = slice
        self.nested = nested
        self.closesMenu = closesMenu
    }
}

struct PanelRow: View {
    @ObservedObject var model: PanelRowModel

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: model.symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(model.warning ? Ink.coral : Ink.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.warning ? Ink.coral : Ink.primary)
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if let checked = model.checked {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(checked ? Ink.mint : Ink.tertiary)
                    .accessibilityHidden(true)
            }
            if !model.shortcut.isEmpty {
                Text(model.shortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Ink.tertiary)
                    .tracking(1)
            }
            if let expanded = model.expanded {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ink.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, model.nested ? 26 : 12)
        .padding(.trailing, 12)
        .frame(height: model.subtitle.isEmpty ? 34 : 42)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(model.highlighted ? Ink.hover : Color.clear)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .frame(width: Ink.panelWidth)
        .padding(.bottom, model.slice.roundsBottom ? 9 : 0)
        .panelSlice(model.slice)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue(model.checked.map { $0 ? "on" : "off" } ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

// Small caps group label inside the settings drawer.
struct PanelLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Ink.inset + 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .frame(width: Ink.panelWidth)
            .panelSlice(.middle)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: 1)
            .padding(.horizontal, Ink.inset)
            .padding(.vertical, 6)
            .frame(width: Ink.panelWidth)
            .panelSlice(.middle)
    }
}

// NSMenu never routes clicks on a custom item view to the item's action, and
// it never draws highlight for one either — the view owns both. This view hosts
// a SwiftUI row, mirrors the item's highlight (mouse and keyboard) into the
// model, and fires the action itself on mouse-up. The NSMenuItem keeps its
// action/target so key equivalents and Return still work natively.
final class PanelRowHostView: NSView {
    let model: PanelRowModel
    private let host: NSHostingView<AnyView>
    private let onClick: (() -> Void)?
    private var mouseInside = false

    init(model: PanelRowModel, onClick: (() -> Void)?) {
        self.model = model
        self.onClick = onClick
        host = NSHostingView(rootView: AnyView(PanelRow(model: model)))
        super.init(frame: .zero)
        let size = host.fittingSize
        frame = NSRect(origin: .zero, size: size)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    static func passive<V: View>(_ view: V) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        return host
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // Clicks anywhere on the row belong to the row, not to the hosted text.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { mouseInside = true; syncHighlight() }
    override func mouseExited(with event: NSEvent) { mouseInside = false; syncHighlight() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        syncHighlight()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A menu that closed and reopened must not keep a stale highlight.
        mouseInside = false
        syncHighlight()
    }

    private func syncHighlight() {
        let enabled = enclosingMenuItem?.isEnabled ?? true
        let h = enabled && (mouseInside || (enclosingMenuItem?.isHighlighted ?? false))
        if model.highlighted != h {
            DispatchQueue.main.async { [model] in model.highlighted = h }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard enclosingMenuItem?.isEnabled ?? true else { return }
        if model.closesMenu { enclosingMenuItem?.menu?.cancelTracking() }
        onClick?()
    }
}

struct WorkWindowCard: View {
    let state: State
    let onToggle: () -> Void
    var slice: PanelSlice = .top

    private let canvas = Ink.canvas
    private let bay = Ink.bay
    private let rail = Ink.rail
    private let line = Ink.line
    private let primary = Ink.primary
    private let secondary = Ink.secondary
    private let accent = Ink.accent
    private let mint = Ink.mint
    private let amber = Ink.amber
    private let coral = Ink.coral

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work window")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(primary)
                    Text(windowDetail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.on ? mint : secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.on },
                    set: { value in if value != state.on { onToggle() } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .accessibilityLabel("Work window")
            }

            HStack(spacing: 10) {
                providerBay("Claude Code", counts: state.claude)
                providerBay("Codex", counts: state.codex)
            }

            HStack(spacing: 7) {
                Image(systemName: "flag.fill")
                Text("Goals")
                    .fontWeight(.semibold)
                Spacer()
                Text(state.goals.isEmpty ? "None registered" : state.goals)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(secondary)

            HStack(spacing: 14) {
                safetyItem("bolt.fill", powerDetail)
                safetyItem("thermometer.medium", state.thermal.isEmpty ? "thermal unknown" : state.thermal)
                safetyItem(state.netOK ? "wifi" : "wifi.slash", networkDetail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(rail))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(line, lineWidth: 1))

            HStack(spacing: 7) {
                Image(systemName: "eye")
                Text("Observed only — agents never control sleep")
                    .foregroundStyle(secondary)
                Spacer()
                Image(systemName: protectionSymbol)
                    .foregroundStyle(protectionColor)
                Text(protectionLabel)
                    .foregroundStyle(protectionColor)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(secondary)
        }
        .padding(Ink.inset)
        .padding(.bottom, slice.roundsBottom ? 0 : -4)
        .frame(width: Ink.panelWidth)
        .panelSlice(slice)
    }

    private var windowDetail: String {
        guard state.on else { return "Off · closing the lid sleeps this Mac" }
        if !state.autoOff.isEmpty && state.autoOff != "n/a" {
            return "On · auto-off in \(state.autoOff)"
        }
        return "On · lid can stay closed"
    }

    private var protectionOK: Bool {
        !state.on || (state.guarded && state.guardian == "running")
    }

    private var protectionLabel: String {
        if !state.on { return "Manual" }
        return protectionOK ? "Protected" : "Guard fault"
    }

    private var protectionSymbol: String {
        if !state.on { return "hand.raised.fill" }
        return protectionOK ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var protectionColor: Color {
        protectionOK ? secondary : coral
    }

    private var powerDetail: String {
        guard !state.power.isEmpty else { return "Power unknown" }
        if state.on && state.onBattery && !state.floor.isEmpty {
            return "\(state.power) · floor \(state.floor)"
        }
        return state.power
    }

    private var networkDetail: String {
        guard !state.net.isEmpty else { return "network unknown" }
        // macOS will not tell a shell script which network it is on — the SSID
        // comes back as "<redacted>" without Location access — so the carrier
        // line reports the one distinction that costs money: an iPhone hotspot
        // is cellular data, and you want to know you are silently on it.
        let onHotspot = state.carrier.contains("hotspot")
        var detail = state.net
        if onHotspot { detail += " · hotspot" }
        if state.on && state.watchdog { detail += " · recovery" }
        return detail
    }

    private func providerBay(_ name: String, counts: AgentCounts) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(counts.active > 0 ? mint : counts.idle > 0 ? amber : secondary.opacity(0.6))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(primary)
                Text(counts.detail)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(counts.active > 0 ? mint : secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 11).fill(bay))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(line, lineWidth: 1))
    }

    private func safetyItem(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(secondary)
    }
}

let placementLogPath = NSString(string: "~/Library/Logs/closedlidawake.log").expandingTildeInPath

func plog(_ msg: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date()))  \(msg)\n"
    NSLog("Closed-Lid Awake: \(msg)")
    guard let data = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: placementLogPath) {
        h.seekToEndOfFile(); h.write(data); try? h.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: placementLogPath))
    }
}

// The notch is not a region macOS will tell you your status item is inside —
// you have to work it out. `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`
// are the two usable strips of menu bar; anything between them is the camera
// housing, and a status item placed there is drawn but invisible.
struct NotchGap {
    let minX: CGFloat
    let maxX: CGFloat

    init?(_ screen: NSScreen) {
        guard screen.safeAreaInsets.top > 0,
              let l = screen.auxiliaryTopLeftArea,
              let r = screen.auxiliaryTopRightArea,
              r.minX > l.maxX else { return nil }
        minX = l.maxX
        maxX = r.minX
    }

    // Any horizontal overlap at all means part of the glyph is eaten. A status
    // item is 24-32pt wide, so a partial overlap is just as unusable as a full one.
    func swallows(_ frame: NSRect) -> Bool { frame.maxX > minX && frame.minX < maxX }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let menu = NSMenu()
    var state = State()
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var hud: NSPanel?
    var hotkeyLabel = ""
    var iconHidden = false
    var warnedAboutHiding = false

    static let autosaveName = "ClosedLidAwakeStatusItem"
    static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
    // AppKit deletes its own autosaved position whenever the item is removed,
    // which the recovery loop does on every attempt — so the hint that finally
    // worked would be forgotten by the next login. Keep our own copy.
    static let lastGoodKey = "LastGoodPreferredPosition"

    let cardItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "Turn Off Work Window", action: #selector(toggle), keyEquivalent: "a")
    let autoItem = NSMenuItem(title: "Enable awake mode at login", action: #selector(toggleAuto), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Show in menu bar at login", action: #selector(toggleLogin), keyEquivalent: "")
    let netLogItem = NSMenuItem(title: "Open Wi-Fi watchdog log", action: #selector(openNetLog), keyEquivalent: "")
    let placementItem = NSMenuItem(title: "Move icon out of the notch", action: #selector(fixPlacement), keyEquivalent: "")
    let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    // Every row below the card is a hosted SwiftUI view drawn from the same
    // palette, so the menu is one panel top to bottom. The NSMenuItems stay
    // real items: titles for accessibility, actions for key equivalents.
    let toggleRow = PanelRowModel(symbol: "power", title: "Turn off work window", subtitle: "Hotkey ⌃⌥A", shortcut: "⌘A")
    let settingsRow = PanelRowModel(symbol: "gearshape.fill", title: "Settings",
                                    subtitle: "Startup · Wi-Fi log · icon placement", expanded: false, closesMenu: false)
    let autoRow = PanelRowModel(symbol: "sunrise.fill", title: "Enable awake mode at login", checked: false, nested: true, closesMenu: false)
    let loginRow = PanelRowModel(symbol: "menubar.rectangle", title: "Show in menu bar at login", checked: false, nested: true, closesMenu: false)
    let netLogRow = PanelRowModel(symbol: "doc.text.magnifyingglass", title: "Open Wi-Fi watchdog log", shortcut: "↗", nested: true)
    let placementRow = PanelRowModel(symbol: "arrow.left.to.line", title: "Move icon out of the notch", nested: true)
    let quitRow = PanelRowModel(symbol: "xmark.square.fill", title: "Quit Closed-Lid Awake", shortcut: "⌘Q", slice: .bottom)

    // Progressive disclosure: the menu opens to the card, the one primary
    // action, and Quit. Startup and tool rows live in a drawer under
    // "Settings" and are hidden NSMenuItems until it is opened.
    let settingsItem = NSMenuItem(title: "Settings", action: #selector(toggleSettings), keyEquivalent: "")
    var drawerItems: [NSMenuItem] = []
    var settingsExpanded = false

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        // The panel is dark by design; the menu chrome around it must be too,
        // or the rounded panel floats on a light frosted slab in light mode.
        menu.appearance = NSAppearance(named: .darkAqua)

        menu.addItem(cardItem)
        menu.addItem(dividerItem())
        attach(toggleItem, toggleRow) { [weak self] in self?.toggle() }
        menu.addItem(dividerItem())
        attach(settingsItem, settingsRow) { [weak self] in self?.toggleSettings() }
        addDrawerItem(passiveItem(PanelLabel(text: "Startup")))
        attach(autoItem, autoRow) { [weak self] in self?.toggleAuto() }
        attach(loginItem, loginRow) { [weak self] in self?.toggleLogin() }
        addDrawerItem(passiveItem(PanelLabel(text: "Tools")))
        attach(netLogItem, netLogRow) { [weak self] in self?.openNetLog() }
        attach(placementItem, placementRow) { [weak self] in self?.fixPlacement() }
        drawerItems.append(contentsOf: [autoItem, loginItem, netLogItem, placementItem])
        addDrawerItem(passiveItem(Color.clear.frame(width: Ink.panelWidth, height: 6).panelSlice(.middle)))
        setDrawer(expanded: false)
        menu.addItem(dividerItem())
        attach(quitItem, quitRow) { NSApp.terminate(nil) }

        makeStatusItem(preferred: UserDefaults.standard.object(forKey: Self.lastGoodKey) as? Double)

        // Honour "enable at login" only when we were started by the LaunchAgent
        // at login, not on a manual relaunch.
        if UserDefaults.standard.bool(forKey: kAutoEnable),
           ProcessInfo.processInfo.environment["CLA_LAUNCHED_AT_LOGIN"] == "1" {
            vibecaf("on")
        }

        registerHotkey()
        refresh()
        // 60s, not 20s. menuWillOpen refreshes on demand, so the timer only has
        // to catch state changed behind the app's back — someone running
        // `vibecaf off` in a terminal, or the guard disarming itself. A minute
        // is ample for that, and it is three times less work while idle.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.refresh() }

        // The menu bar is still settling at login — every other login item is
        // claiming its slot at the same moment — so measuring immediately reads
        // a layout that is about to change. Wait for it to stop moving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.verifyPlacement(recover: true) }

        // Connecting or disconnecting a display re-lays out the whole bar, and
        // that is the usual moment an icon that was fine yesterday goes missing.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.verifyPlacement(recover: true) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.verifyPlacement(recover: true) }
        }
    }

    // ── menu bar placement ───────────────────────────────────────────────────

    func makeStatusItem(preferred: Double?) {
        if let old = item { NSStatusBar.system.removeStatusItem(old) }
        // The position hint has to be written before the item exists: NSStatusItem
        // reads this default at creation and overwrites it with wherever it
        // actually landed, so writing it to a live item does nothing.
        if let p = preferred { UserDefaults.standard.set(p, forKey: Self.positionKey) }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Without an autosaveName macOS forgets where you ⌘-dragged this item,
        // so it drifts back to the left edge at every login — which on a notched
        // display means straight back behind the notch, invisible.
        item.autosaveName = Self.autosaveName
        item.menu = menu
        item.button?.image = currentImage()
    }

    func itemFrame() -> (NSRect, NSScreen)? {
        guard let win = item.button?.window else { return nil }
        guard let scr = win.screen ?? NSScreen.main else { return nil }
        return (win.frame, scr)
    }

    // Three places a status item can end up on a notched Mac, in descending
    // order of usefulness. `left` is not a win: that strip belongs to the
    // frontmost app's menus, so the icon is visible under Finder and buried
    // under anything with a long menu bar. It beats the notch and nothing else.
    enum Placement: Int { case right = 0, left = 1, notch = 2 }

    func placement() -> Placement {
        guard let (frame, scr) = itemFrame(), item.isVisible else { return .notch }
        guard let gap = NotchGap(scr) else { return .right }   // no notch, nowhere to hide
        if gap.swallows(frame) { return .notch }
        return frame.minX >= gap.maxX ? .right : .left
    }

    func isIconHidden() -> Bool { placement() == .notch }

    @objc func fixPlacement() { verifyPlacement(recover: true, force: true) }

    func verifyPlacement(recover: Bool, force: Bool = false) {
        guard let (frame, scr) = itemFrame() else {
            plog("placement: no status item window yet")
            return
        }
        let gap = NotchGap(scr)
        let desc = "x=\(Int(frame.minX))-\(Int(frame.maxX)) on \(Int(scr.frame.width))pt screen"
            + (gap.map { ", notch \(Int($0.minX))-\(Int($0.maxX))" } ?? ", no notch")
        let here = placement()

        if here == .right && !force {
            iconHidden = false
            plog("placement OK (right of notch): \(desc)")
            applyState()
            return
        }

        plog("placement \(here): \(desc)")
        guard recover else { iconHidden = (here == .notch); applyState(); return }

        // Try each hint and keep the best result, rather than the first tolerable
        // one. LOWER preferred positions land further right — measured, and the
        // opposite of what the name suggests. The mapping is undocumented and
        // depends on what every other menu bar app asked for, so the ladder is
        // ordered best-guess-first but every rung is still measured.
        var best: (score: Placement, hint: Double, frame: NSRect) = (here, UserDefaults.standard.double(forKey: Self.positionKey), frame)
        for candidate in [0.0, 1.0, 100.0, 1_000.0, 10_000.0, 1_000_000.0] {
            makeStatusItem(preferred: candidate)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let got = placement()
            if let (f, _) = itemFrame() {
                plog("  try preferred=\(Int(candidate)) → \(got) x=\(Int(f.minX))-\(Int(f.maxX))")
                if got.rawValue < best.score.rawValue { best = (got, candidate, f) }
            }
            if got == .right { break }
        }

        // Re-apply the winner, since the last thing we tried is probably not it.
        if let (f, _) = itemFrame(), f != best.frame || placement() != best.score {
            makeStatusItem(preferred: best.hint)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }

        iconHidden = (best.score == .notch)
        if best.score != .notch {
            UserDefaults.standard.set(best.hint, forKey: Self.lastGoodKey)
        }
        switch best.score {
        case .right: plog("recovered: preferred=\(Int(best.hint)) → right of notch at x=\(Int(best.frame.minX))")
        case .left:  plog("best available is LEFT of the notch (x=\(Int(best.frame.minX))) — visible, but app menus can cover it. The right-hand menu bar is full.")
        case .notch: plog("could not place the icon outside the notch — the menu bar is full")
        }
        applyState()
        if best.score == .notch && !warnedAboutHiding {
            warnedAboutHiding = true
            showNotchWarning()
        }
    }

    func showNotchWarning() {
        let a = NSAlert()
        a.messageText = "Menu bar icon has nowhere to go"
        a.informativeText = """
            The menu bar to the right of the notch is full, so this icon is being \
            drawn behind the notch where you cannot see or click it.

            Awake mode still works. Use the \(hotkeyLabel.isEmpty ? "global hotkey" : hotkeyLabel) hotkey, \
            Raycast, or `vibecaf toggle` in a terminal.

            To get the icon back, quit a few other menu bar apps — or ⌘-drag this \
            one to an empty slot once it appears.
            """
        a.alertStyle = .informational
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // Draw what we already know instantly, then go and get a fresh reading —
    // including a real network probe, since a menu the user just opened is the
    // one moment the 8.5s worst case is worth paying for. The menu updates in
    // place when it lands.
    private func attach(_ item: NSMenuItem, _ model: PanelRowModel, onClick: @escaping () -> Void) {
        if item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        item.view = PanelRowHostView(model: model, onClick: onClick)
        menu.addItem(item)
    }

    private func dividerItem() -> NSMenuItem { passiveItem(PanelDivider()) }

    // A non-interactive slice of the panel (divider, group label). Kept
    // disabled so keyboard navigation skips it. The caller adds it to the menu.
    private func passiveItem<V: View>(_ view: V) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = PanelRowHostView.passive(view)
        item.isEnabled = false
        return item
    }

    private func addDrawerItem(_ item: NSMenuItem) {
        menu.addItem(item)
        drawerItems.append(item)
    }

    @objc func toggleSettings() { setDrawer(expanded: !settingsExpanded) }

    func setDrawer(expanded: Bool) {
        settingsExpanded = expanded
        settingsRow.expanded = expanded
        for item in drawerItems { item.isHidden = !expanded }
    }

    // Open to the summary every time; a drawer that remembers being open is a
    // wall of controls again. The one exception is a fault the user must act
    // on: if the icon is lost behind the notch, open straight to the fix.
    func menuDidClose(_ menu: NSMenu) {
        setDrawer(expanded: false)
    }

    func menuWillOpen(_ menu: NSMenu) {
        setDrawer(expanded: iconHidden)
        applyState()
        refresh(probeNet: true)
    }

    func currentImage() -> NSImage? {
        let symbol = state.on ? "cup.and.saucer.fill" : "moon.zzz.fill"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Closed-Lid Awake")
        img?.isTemplate = true
        return img
    }

    // Fetch off the main thread, always. `vibecaf status` forks pmset, and with
    // --net it can block for 8.5s on a dead network. This used to run
    // synchronously on a 20s timer, which stalled the menu bar for 8.5 of every
    // 20 seconds exactly when the network was bad — the one situation the app
    // exists for, and the one where you most need the icon to respond.
    func refresh(probeNet: Bool = false) {
        DispatchQueue.global(qos: .utility).async {
            let s = readState(probeNet: probeNet)
            DispatchQueue.main.async { self.state = s; self.applyState() }
        }
    }

    // Pure UI, no subprocesses — safe to call on the main thread as often as
    // you like, and the only thing that touches AppKit.
    func applyState() {
        item.button?.image = currentImage()
        item.button?.toolTip = state.on ? "Awake mode ON — lid can stay closed" : "Awake mode off — closing the lid sleeps this Mac"
        updateStatusCard()

        placementItem.title = iconHidden
            ? "Icon is behind the notch — try to move it"
            : "Move icon out of the notch"
        placementRow.title = placementItem.title
        placementRow.symbol = iconHidden ? "exclamationmark.triangle.fill" : "arrow.left.to.line"
        placementRow.warning = iconHidden
        settingsRow.warning = iconHidden
        settingsRow.symbol = iconHidden ? "exclamationmark.triangle.fill" : "gearshape.fill"
        settingsRow.subtitle = iconHidden ? "Icon is behind the notch — fix below" : "Startup · Wi-Fi log · icon placement"

        toggleItem.title = state.on ? "Turn Off Work Window" : "Turn On Work Window"
        toggleRow.title = state.on ? "Turn off work window" : "Turn on work window"
        toggleRow.symbol = state.on ? "moon.zzz.fill" : "cup.and.saucer.fill"
        toggleRow.subtitle = "Hotkey \(hotkeyLabel)"

        let autoOn = UserDefaults.standard.bool(forKey: kAutoEnable)
        let loginOn = FileManager.default.fileExists(atPath: agentPlist)
        autoItem.state = autoOn ? .on : .off
        loginItem.state = loginOn ? .on : .off
        autoRow.checked = autoOn
        loginRow.checked = loginOn
    }

    func updateStatusCard() {
        let view = WorkWindowCard(state: state) { [weak self] in self?.toggle() }
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        cardItem.view = host
    }

    @objc func toggle() {
        let turningOn = !state.on
        // Run off the main thread: `vibecaf on` spawns caffeinate and the
        // watchdog, and a beachballing menu bar item you can't even see is a
        // particularly unhelpful failure mode.
        DispatchQueue.global(qos: .userInitiated).async {
            vibecaf(turningOn ? "on" : "off")
            DispatchQueue.main.async {
                self.refresh()
                self.showHUD(turningOn)
            }
        }
    }

    // On a notched display the status item can end up hidden behind the notch
    // with no way to move it, so the hotkey needs its own visible confirmation.
    func showHUD(_ on: Bool) {
        let text = on ? "Awake mode ON — lid can stay closed" : "Awake mode OFF"
        let symbol = on ? "cup.and.saucer.fill" : "moon.zzz.fill"

        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.textColor = .labelColor
        field.sizeToFit()

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        iconView.contentTintColor = .labelColor
        iconView.frame = NSRect(x: 22, y: 20, width: 26, height: 26)

        let w = field.frame.width + 80, h: CGFloat = 66
        field.frame = NSRect(x: 58, y: (h - field.frame.height) / 2,
                             width: field.frame.width, height: field.frame.height)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.addSubview(iconView)
        blur.addSubview(field)
        panel.contentView = blur

        if let scr = NSScreen.main {
            let f = scr.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - w / 2, y: f.minY + 120))
        }
        panel.orderFrontRegardless()
        hud?.close()
        hud = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak panel] in
            guard let p = panel, p === self.hud else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                p.animator().alphaValue = 0
            }, completionHandler: { p.close(); if self.hud === p { self.hud = nil } })
        }
    }

    // Default ⌃⌥A. Carbon's RegisterEventHotKey is used rather than an NSEvent
    // global monitor because the latter needs Accessibility permission and this
    // does not. Overridable without a rebuild:
    //   defaults write app.closedlidawake.ClosedLidAwake HotkeyKeyCode  -int 0   # 0 = A
    //   defaults write app.closedlidawake.ClosedLidAwake HotkeyModifiers -int 3  # 1=⌘ 2=⇧ 4=⌥ 8=⌃, summed
    func registerHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.toggle()
            }
            return noErr
        }, 1, &spec, nil, nil)

        let d = UserDefaults.standard
        let key = d.object(forKey: "HotkeyKeyCode") as? Int ?? kVK_ANSI_A
        // Simple 1/2/4/8 flags rather than raw Carbon constants, so the
        // `defaults write` above stays something a human can compose.
        var wanted: [(UInt32, String)] = []
        if let m = d.object(forKey: "HotkeyModifiers") as? Int {
            var carbon: UInt32 = 0, label = ""
            if m & 8 != 0 { carbon |= UInt32(controlKey); label += "⌃" }
            if m & 4 != 0 { carbon |= UInt32(optionKey);  label += "⌥" }
            if m & 2 != 0 { carbon |= UInt32(shiftKey);   label += "⇧" }
            if m & 1 != 0 { carbon |= UInt32(cmdKey);     label += "⌘" }
            wanted.append((carbon, label))
        }
        // Fallbacks, in order, if the preferred combo is already taken system-wide.
        wanted.append((UInt32(controlKey | optionKey), "⌃⌥"))
        wanted.append((UInt32(controlKey | optionKey | cmdKey), "⌃⌥⌘"))

        let keyName = key == kVK_ANSI_A ? "A" : "key\(key)"
        for (mods, label) in wanted {
            let hkID = EventHotKeyID(signature: OSType(0x434C4157), id: 1)  // 'CLAW'
            let status = RegisterEventHotKey(UInt32(key), mods, hkID,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
            if status == noErr {
                hotkeyLabel = label + keyName
                NSLog("Closed-Lid Awake: hotkey \(hotkeyLabel) registered")
                return
            }
            NSLog("Closed-Lid Awake: \(label)\(keyName) unavailable (\(status)) — trying next")
        }
        hotkeyLabel = "unavailable — all combos taken"
    }

    @objc func openNetLog() {
        let log = NSString(string: "~/Library/Logs/vibecaf-net.log").expandingTildeInPath
        if !FileManager.default.fileExists(atPath: log) {
            FileManager.default.createFile(atPath: log, contents: Data())
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: log))
    }

    @objc func toggleAuto() {
        let v = !UserDefaults.standard.bool(forKey: kAutoEnable)
        UserDefaults.standard.set(v, forKey: kAutoEnable)
        applyState()
    }

    @objc func toggleLogin() {
        let fm = FileManager.default
        let uid = getuid()
        if fm.fileExists(atPath: agentPlist) {
            shell("/bin/launchctl", ["bootout", "gui/\(uid)/\(agentLabel)"])
            try? fm.removeItem(atPath: agentPlist)
        } else {
            let exe = Bundle.main.executablePath ?? ""
            let plist: [String: Any] = [
                "Label": agentLabel,
                "ProgramArguments": [exe],
                "EnvironmentVariables": ["CLA_LAUNCHED_AT_LOGIN": "1"],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua",
            ]
            let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try? fm.createDirectory(atPath: (agentPlist as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            try? data?.write(to: URL(fileURLWithPath: agentPlist))
            shell("/bin/launchctl", ["bootstrap", "gui/\(uid)", agentPlist])
        }
        applyState()
    }

    @discardableResult
    func shell(_ cmd: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        p.standardError = Pipe()
        p.standardOutput = Pipe()
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

#if CARD_PREVIEW
let previewApp = NSApplication.shared
previewApp.setActivationPolicy(.regular)
let previewState = State(
    on: true,
    power: "AC 100%",
    net: "online",
    netOK: true,
    carrier: "Wi-Fi",
    guarded: true,
    guardian: "running",
    autoOff: "5h 42m",
    floor: "20%",
    thermal: "nominal",
    goals: "4 active · 1 stalled",
    claude: AgentCounts(active: 2, idle: 1, completed: 0),
    codex: AgentCounts(active: 3, idle: 0, completed: 1)
)
private let previewExpanded = ProcessInfo.processInfo.environment["VIBECAF_CARD_PREVIEW_EXPANDED"] == "1"
private let previewRows: [PanelRowModel] = [
    PanelRowModel(symbol: "moon.zzz.fill", title: "Turn off work window", subtitle: "Hotkey ⌃⌥A", shortcut: "⌘A"),
    PanelRowModel(symbol: "gearshape.fill", title: "Settings", subtitle: "Startup · Wi-Fi log · icon placement", expanded: previewExpanded),
    PanelRowModel(symbol: "sunrise.fill", title: "Enable awake mode at login", checked: true, nested: true),
    PanelRowModel(symbol: "menubar.rectangle", title: "Show in menu bar at login", checked: false, nested: true),
    PanelRowModel(symbol: "doc.text.magnifyingglass", title: "Open Wi-Fi watchdog log", shortcut: "↗", nested: true),
    PanelRowModel(symbol: "arrow.left.to.line", title: "Move icon out of the notch", nested: true),
    PanelRowModel(symbol: "xmark.square.fill", title: "Quit Closed-Lid Awake", shortcut: "⌘Q", slice: .bottom),
]
previewRows[previewExpanded ? 4 : 1].highlighted = true
private let previewPanel = VStack(spacing: 0) {
    WorkWindowCard(state: previewState, onToggle: {})
    PanelDivider()
    PanelRow(model: previewRows[0])
    PanelDivider()
    PanelRow(model: previewRows[1])
    if previewExpanded {
        PanelLabel(text: "Startup")
        PanelRow(model: previewRows[2])
        PanelRow(model: previewRows[3])
        PanelLabel(text: "Tools")
        PanelRow(model: previewRows[4])
        PanelRow(model: previewRows[5])
        Color.clear.frame(width: Ink.panelWidth, height: 6).panelSlice(.middle)
    }
    PanelDivider()
    PanelRow(model: previewRows[6])
}
.padding(12)
.background(Color(red: 0.16, green: 0.17, blue: 0.2))
.environment(\.colorScheme, .dark)
private let previewHost = NSHostingView(rootView: previewPanel)
previewHost.frame = NSRect(origin: .zero, size: previewHost.fittingSize)
previewHost.layoutSubtreeIfNeeded()
if let output = ProcessInfo.processInfo.environment["VIBECAF_CARD_PREVIEW_PATH"],
   let bitmap = previewHost.bitmapImageRepForCachingDisplay(in: previewHost.bounds) {
    previewHost.cacheDisplay(in: previewHost.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
} else {
    let previewWindow = NSWindow(
        contentRect: previewHost.bounds,
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    previewWindow.title = "Work Window Card Preview"
    previewWindow.contentView = previewHost
    previewWindow.center()
    previewWindow.makeKeyAndOrderFront(nil)
    previewApp.activate(ignoringOtherApps: true)
    previewApp.run()
}
#else
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#endif
