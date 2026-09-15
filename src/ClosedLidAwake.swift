// Closed-Lid Awake — menu bar control for ~/.local/bin/vibecaf
import AppKit
import Carbon.HIToolbox
import SwiftUI
import Combine

let bundledVibecafPath = Bundle.main.url(forResource: "vibecaf", withExtension: nil)?.path
let vibecafPath = bundledVibecafPath
    ?? NSString(string: "~/.local/bin/vibecaf").expandingTildeInPath
let agentLabel = Bundle.main.bundleIdentifier ?? "app.closedlidawake.ClosedLidAwake"
let agentPlist = NSString(string: "~/Library/LaunchAgents/\(agentLabel).plist").expandingTildeInPath
let kAutoEnable = "autoEnableAtLogin"

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
    @Published var enabled = true
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
        .opacity(model.enabled ? 1 : 0.46)
        .disabled(!model.enabled)
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

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { model.title }
    override func accessibilityHelp() -> String? { model.subtitle }
    override func accessibilityValue() -> Any? { model.checked.map { $0 ? "on" : "off" } }
    override func isAccessibilityEnabled() -> Bool { enclosingMenuItem?.isEnabled ?? model.enabled }
    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityEnabled() else { return false }
        if model.closesMenu { enclosingMenuItem?.menu?.cancelTracking() }
        onClick?()
        return true
    }

    override func mouseUp(with event: NSEvent) {
        guard enclosingMenuItem?.isEnabled ?? true else { return }
        if model.closesMenu { enclosingMenuItem?.menu?.cancelTracking() }
        onClick?()
    }
}

// NSMenu uses the custom view’s frame, not just its intrinsic size. Keep the same
// host alive while allowing long faults and Activity expansion to grow its row.
final class ResizingCardHost<Content: View>: NSHostingView<Content> {
    private var observation: AnyCancellable?
    func observe(_ model: WorkWindowCardModel) {
        observation = model.objectWillChange.sink { [weak self] _ in
            // Published state changes before the queued pass runs. Allow SwiftUI
            // to recompute its fitting size before changing the menu item frame.
            DispatchQueue.main.async {
                guard let self else { return }
                let size = self.fittingSize
                if abs(self.frame.height - size.height) > 0.5 || abs(self.frame.width - size.width) > 0.5 {
                    self.setFrameSize(size)
                    self.enclosingMenuItem?.menu?.update()
                }
            }
        }
    }
}

final class WorkWindowCardModel: ObservableObject {
    @Published var state: State
    @Published var activityExpanded = false

    init(state: State) { self.state = state }
}

struct WorkWindowCard: View {
    @ObservedObject var model: WorkWindowCardModel
    let onToggle: () -> Void
    let onDurationChange: (Int) -> Void
    let onCheckSetup: () -> Void
    var slice: PanelSlice = .top

    private let canvas = Ink.canvas
    private let bay = Ink.bay
    private let rail = Ink.rail
    private let line = Ink.line
    private let primary = Ink.primary
    private let secondary = Ink.secondary
    private let tertiary = Ink.tertiary
    private let accent = Ink.accent
    private let mint = Ink.mint
    private let amber = Ink.amber
    private let coral = Ink.coral

    private var state: State { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work window")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(primary)
                    Text(windowDetail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(state.ownsSession ? mint : secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.ownsSession },
                    set: { value in if value != state.ownsSession { onToggle() } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(accent)
                .disabled(!primaryControlEnabled)
                .accessibilityLabel(primaryControlLabel)
                .accessibilityHint(primaryControlHint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(state.ownsSession ? "Next session duration" : "Session duration")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(tertiary)
                    .textCase(.uppercase)
                Picker("Session duration", selection: Binding(
                    get: { SessionDuration.presets.contains(state.selectedDuration) ? state.selectedDuration : 21_600 },
                    set: onDurationChange
                )) {
                    ForEach(SessionDuration.presets, id: \.self) { seconds in
                        Text(SessionDuration.label(for: seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(state.pending != nil)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    safetyItem("bolt.fill", powerDetail)
                    safetyItem("thermometer.medium", state.thermal ?? "thermal unknown")
                    safetyItem(state.networkState == "online" ? "wifi" : "wifi.slash", networkDetail)
                }
                VStack(alignment: .leading, spacing: 6) {
                    safetyItem("bolt.fill", powerDetail)
                    safetyItem("thermometer.medium", state.thermal ?? "thermal unknown")
                    safetyItem(state.networkState == "online" ? "wifi" : "wifi.slash", networkDetail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(rail))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(line, lineWidth: 1))

            if let faultText {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(coral)
                        Text(faultText)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Check setup", action: onCheckSetup)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(coral.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(coral.opacity(0.45), lineWidth: 1))
            }

            HStack(spacing: 7) {
                Image(systemName: protectionSymbol)
                .foregroundStyle(protectionColor)
                Text(protectionLabel)
                    .foregroundStyle(protectionColor)
                Spacer()
                if hasActivity {
                    Button {
                        model.activityExpanded.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eye")
                            Text("Activity")
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(model.activityExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.activityExpanded ? "Hide activity" : "Show activity")
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(secondary)

            if hasActivity && model.activityExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        if !state.agents.claude.isEmpty { providerBay("Claude Code", counts: state.agents.claude) }
                        if !state.agents.codex.isEmpty { providerBay("Codex", counts: state.agents.codex) }
                    }
                    if !state.goals.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: "flag.fill")
                            Text("Goals").fontWeight(.semibold)
                            Spacer()
                            Text(state.goals.detail).monospacedDigit()
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(secondary)
                    }
                    Text("Observed only · agents never control sleep")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(tertiary)
                }
            }
        }
        .padding(Ink.inset)
        .padding(.bottom, slice.roundsBottom ? 0 : -4)
        .frame(width: Ink.panelWidth)
        .panelSlice(slice)
    }

    private var windowDetail: String {
        if let pending = state.pending { return pending.label }
        switch state.phase {
        case .off:
            return "Off · closing the lid uses normal sleep"
        case .ownedOn:
            guard let deadline = state.deadline else { return "On · end time unavailable" }
            let end = Date(timeIntervalSince1970: deadline)
            let remaining = max(0, Int(deadline - Date().timeIntervalSince1970))
            return "Ends \(Self.clock.string(from: end)) · \(Self.remaining(remaining)) left"
        case .externalOn:
            return "Another tool is preventing sleep"
        case .unknown:
            return "State unavailable · check setup"
        }
    }

    private var primaryControlEnabled: Bool {
        state.pending == nil && (state.phase == .off || state.phase == .ownedOn)
    }

    private var primaryControlLabel: String {
        state.ownsSession ? "Turn off work window" : "Turn on work window"
    }

    private var primaryControlHint: String {
        if state.isExternallyHeld { return "Another tool owns the current sleep hold." }
        if state.phase == .unknown { return "Check setup before changing awake state." }
        return hotToggleHint
    }

    private var hotToggleHint: String { "Changes the manual, time-bounded awake session." }

    private var hasActivity: Bool {
        !state.agents.claude.isEmpty || !state.agents.codex.isEmpty || !state.goals.isEmpty
    }

    private var protectionLabel: String {
        switch state.phase {
        case .off: return "Manual control"
        case .ownedOn: return state.recoveryReady ? "Recovery ready" : "Recovery needs attention"
        case .externalOn: return "External hold · unchanged"
        case .unknown: return "Unverified"
        }
    }

    private var protectionSymbol: String {
        switch state.phase {
        case .off: return "hand.raised.fill"
        case .ownedOn: return state.recoveryReady ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        case .externalOn: return "person.crop.circle.badge.exclamationmark"
        case .unknown: return "questionmark.diamond.fill"
        }
    }

    private var protectionColor: Color {
        state.phase == .ownedOn && !state.recoveryReady || state.phase == .unknown ? coral : secondary
    }

    private var powerDetail: String {
        var result = state.powerSource ?? "Power unknown"
        if let percent = state.batteryPercent { result += " \(percent)%" }
        if state.ownsSession && (state.powerSource?.lowercased().contains("battery") ?? false) {
            result += " · floor \(state.batteryFloor)%"
        }
        return result
    }

    private var networkDetail: String {
        var detail = state.networkDetail.isEmpty ? state.networkState : state.networkDetail
        if state.ownsSession && state.networkRecovery { detail += " · monitoring" }
        return detail
    }

    private var faultText: String? {
        if let error = state.commandError, !error.isEmpty { return error }
        guard !state.issues.isEmpty else { return nil }
        let first = state.issues[0]
        return state.issues.count == 1 ? first : "\(first) (+\(state.issues.count - 1) more)"
    }

    private func providerBay(_ name: String, counts: AgentCounts) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(counts.working > 0 ? mint : counts.quiet > 0 ? amber : secondary.opacity(0.6))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(primary)
                Text(counts.detail)
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(counts.working > 0 ? mint : secondary)
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static func remaining(_ seconds: Int) -> String {
        if seconds < 60 { return "<1m" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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
        let size = h.seekToEndOfFile()
        if size > 64 * 1024 {
            try? h.close()
            // Placement logs are diagnostic only; retain a bounded recent tail.
            if let reader = FileHandle(forReadingAtPath: placementLogPath) {
                try? reader.seek(toOffset: size - 32 * 1024)
                let tail = (try? reader.readToEnd()) ?? Data()
                try? reader.close()
                try? (tail + data).write(to: URL(fileURLWithPath: placementLogPath), options: .atomic)
            }
        } else {
            h.write(data); try? h.close()
        }
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
    let cardModel = WorkWindowCardModel(state: State())
    let runner: CommandRunning = ProcessRunner()
    let mutationQueue = DispatchQueue(label: "app.closedlidawake.mutations", qos: .userInitiated)
    let revisionGate = RevisionGate()
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var hotKeyHandlerRef: EventHandlerRef?
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
    let autoItem = NSMenuItem(title: "Enable awake mode at login", action: #selector(toggleAuto), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Show in menu bar at login", action: #selector(toggleLogin), keyEquivalent: "")
    let recoveryItem = NSMenuItem(title: "Network monitoring", action: #selector(toggleRecovery), keyEquivalent: "")
    let notificationsItem = NSMenuItem(title: "Notify when agent work changes", action: #selector(toggleNotifications), keyEquivalent: "")
    let shortcutItem = NSMenuItem(title: "Keyboard shortcut", action: #selector(configureShortcut), keyEquivalent: "")
    let doctorItem = NSMenuItem(title: "Check setup", action: #selector(checkSetup), keyEquivalent: "")
    let netLogItem = NSMenuItem(title: "Open Wi-Fi watchdog log", action: #selector(openNetLog), keyEquivalent: "")
    let placementItem = NSMenuItem(title: "Move icon out of the notch", action: #selector(fixPlacement), keyEquivalent: "")
    let updatesItem = NSMenuItem(title: "Check for updates", action: #selector(openUpdates), keyEquivalent: "")
    let supportItem = NSMenuItem(title: "Report a problem", action: #selector(openSupport), keyEquivalent: "")
    let aboutItem = NSMenuItem(title: "About Closed-Lid Awake", action: #selector(showAbout), keyEquivalent: "")
    let quitItem = NSMenuItem(title: "Quit menu bar app", action: #selector(quitApp), keyEquivalent: "q")
    let turnOffQuitItem = NSMenuItem(title: "Turn off and quit", action: #selector(turnOffAndQuit), keyEquivalent: "")

    // Every row below the card is a hosted SwiftUI view drawn from the same
    // palette, so the menu is one panel top to bottom. The NSMenuItems stay
    // real items: titles for accessibility, actions for key equivalents.
    let settingsRow = PanelRowModel(symbol: "gearshape.fill", title: "Settings",
                                    subtitle: "Session · startup · diagnostics", expanded: false, closesMenu: false)
    let autoRow = PanelRowModel(symbol: "sunrise.fill", title: "Enable awake mode at login", checked: false, nested: true, closesMenu: false)
    let loginRow = PanelRowModel(symbol: "menubar.rectangle", title: "Show in menu bar at login", checked: false, nested: true, closesMenu: false)
    let recoveryRow = PanelRowModel(symbol: "wifi", title: "Network monitoring", subtitle: "Read-only checks; no network settings change", checked: true, nested: true, closesMenu: false)
    let notificationsRow = PanelRowModel(symbol: "bell", title: "Notify when agent work changes", checked: false, nested: true, closesMenu: false)
    let shortcutRow = PanelRowModel(symbol: "keyboard", title: "Keyboard shortcut", nested: true)
    let doctorRow = PanelRowModel(symbol: "stethoscope", title: "Check setup", subtitle: "Copyable, read-only diagnostics", nested: true)
    let netLogRow = PanelRowModel(symbol: "doc.text.magnifyingglass", title: "Open Wi-Fi watchdog log", shortcut: "↗", nested: true)
    let placementRow = PanelRowModel(symbol: "arrow.left.to.line", title: "Move icon out of the notch", nested: true)
    let updatesRow = PanelRowModel(symbol: "arrow.down.circle", title: "Check for updates", shortcut: "↗", nested: true)
    let supportRow = PanelRowModel(symbol: "ladybug", title: "Report a problem", shortcut: "↗", nested: true)
    let aboutRow = PanelRowModel(symbol: "info.circle", title: "About Closed-Lid Awake", nested: true)
    let turnOffQuitRow = PanelRowModel(symbol: "power", title: "Turn off and quit", subtitle: "Restore normal sleep first")
    let quitRow = PanelRowModel(symbol: "xmark.square.fill", title: "Quit menu bar app", shortcut: "⌘Q", slice: .bottom)

    // Progressive disclosure: the menu opens to the card, the one primary
    // action, and Quit. Startup and tool rows live in a drawer under
    // "Settings" and are hidden NSMenuItems until it is opened.
    let settingsItem = NSMenuItem(title: "Settings", action: #selector(toggleSettings), keyEquivalent: "")
    var drawerItems: [NSMenuItem] = []
    var settingsExpanded = false

    func applicationDidFinishLaunching(_ n: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        menu.delegate = self
        // The panel is dark by design; the menu chrome around it must be too,
        // or the rounded panel floats on a light frosted slab in light mode.
        menu.appearance = NSAppearance(named: .darkAqua)

        installStatusCard()
        menu.addItem(dividerItem())
        attach(settingsItem, settingsRow) { [weak self] in self?.toggleSettings() }
        addDrawerItem(passiveItem(PanelLabel(text: "Session")))
        attach(recoveryItem, recoveryRow) { [weak self] in self?.toggleRecovery() }
        attach(notificationsItem, notificationsRow) { [weak self] in self?.toggleNotifications() }
        attach(shortcutItem, shortcutRow) { [weak self] in self?.configureShortcut() }
        drawerItems.append(contentsOf: [recoveryItem, notificationsItem, shortcutItem])
        addDrawerItem(passiveItem(PanelLabel(text: "Startup")))
        attach(autoItem, autoRow) { [weak self] in self?.toggleAuto() }
        attach(loginItem, loginRow) { [weak self] in self?.toggleLogin() }
        drawerItems.append(contentsOf: [autoItem, loginItem])
        addDrawerItem(passiveItem(PanelLabel(text: "Diagnostics")))
        attach(doctorItem, doctorRow) { [weak self] in self?.checkSetup() }
        attach(netLogItem, netLogRow) { [weak self] in self?.openNetLog() }
        attach(placementItem, placementRow) { [weak self] in self?.fixPlacement() }
        drawerItems.append(contentsOf: [doctorItem, netLogItem, placementItem])
        addDrawerItem(passiveItem(PanelLabel(text: "Help")))
        attach(updatesItem, updatesRow) { [weak self] in self?.openUpdates() }
        attach(supportItem, supportRow) { [weak self] in self?.openSupport() }
        attach(aboutItem, aboutRow) { [weak self] in self?.showAbout() }
        drawerItems.append(contentsOf: [updatesItem, supportItem, aboutItem])
        addDrawerItem(passiveItem(Color.clear.frame(width: Ink.panelWidth, height: 6).panelSlice(.middle)))
        setDrawer(expanded: false)
        menu.addItem(dividerItem())
        attach(turnOffQuitItem, turnOffQuitRow) { [weak self] in self?.turnOffAndQuit() }
        attach(quitItem, quitRow) { [weak self] in self?.quitApp() }

        makeStatusItem(preferred: UserDefaults.standard.object(forKey: Self.lastGoodKey) as? Double)

        // Honour "enable at login" only when we were started by the LaunchAgent
        // at login, not on a manual relaunch.
        registerHotkey()
        if UserDefaults.standard.bool(forKey: kAutoEnable),
           ProcessInfo.processInfo.environment["CLA_LAUNCHED_AT_LOGIN"] == "1" {
            performMutation(arguments: ["on"], pending: .turningOn, expected: .ownedOn)
        } else {
            refresh()
        }
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
        let symbol: String
        switch state.phase {
        case .ownedOn: symbol = "cup.and.saucer.fill"
        case .externalOn: symbol = "person.crop.circle.badge.exclamationmark"
        case .unknown: symbol = "questionmark.diamond.fill"
        case .off: symbol = "moon.zzz.fill"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Closed-Lid Awake")
        img?.isTemplate = true
        return img
    }

    func refresh(probeNet: Bool = false) {
        guard state.pending == nil else { return }
        let revision = revisionGate.issue()
        DispatchQueue.global(qos: .utility).async {
            var arguments = ["status", "--json"]
            if probeNet { arguments.append("--net") }
            let result = self.runner.run(executable: vibecafPath, arguments: arguments,
                                         timeout: probeNet ? 12 : 5)
            let parsed: Result<State, Error>
            if result.succeeded {
                do { parsed = .success(try StatusParser.parse(result.stdout)) }
                catch { parsed = .failure(error) }
            } else {
                parsed = .failure(NSError(domain: agentLabel, code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: result.failureDescription]))
            }
            DispatchQueue.main.async {
                guard self.revisionGate.accepts(revision), self.state.pending == nil else { return }
                switch parsed {
                case .success(let newState): self.state = newState
                case .failure(let error): self.state = .unavailable(error.localizedDescription)
                }
                self.applyState()
            }
        }
    }

    // Pure UI, no subprocesses — safe to call on the main thread as often as
    // you like, and the only thing that touches AppKit.
    func applyState() {
        item.button?.image = currentImage()
        switch state.phase {
        case .ownedOn: item.button?.toolTip = "Work window on until its shown deadline"
        case .externalOn: item.button?.toolTip = "Another tool is preventing sleep"
        case .unknown: item.button?.toolTip = "Awake state unavailable — check setup"
        case .off: item.button?.toolTip = "Work window off — normal sleep applies"
        }
        updateStatusCard()

        placementItem.title = iconHidden
            ? "Icon is behind the notch — try to move it"
            : "Move icon out of the notch"
        placementRow.title = placementItem.title
        placementRow.symbol = iconHidden ? "exclamationmark.triangle.fill" : "arrow.left.to.line"
        placementRow.warning = iconHidden
        settingsRow.warning = iconHidden
        settingsRow.symbol = iconHidden ? "exclamationmark.triangle.fill" : "gearshape.fill"
        settingsRow.subtitle = iconHidden ? "Icon is behind the notch — fix below" : "Session · startup · diagnostics"

        let autoOn = UserDefaults.standard.bool(forKey: kAutoEnable)
        let loginOn = FileManager.default.fileExists(atPath: agentPlist)
        autoItem.state = autoOn ? .on : .off
        loginItem.state = loginOn ? .on : .off
        autoRow.checked = autoOn
        loginRow.checked = loginOn
        autoItem.isEnabled = loginOn && state.pending == nil
        autoRow.enabled = autoItem.isEnabled
        autoRow.subtitle = loginOn ? "Starts a bounded session with the menu bar app" : "Turn on menu bar login first"
        recoveryRow.checked = state.networkRecovery
        recoveryRow.subtitle = state.networkRecoveryAvailable == false
            ? "Read-only checks · repair guidance only"
            : "Read-only checks; no network settings change"
        notificationsRow.checked = state.agentNotifications
        shortcutRow.subtitle = hotkeyLabel.isEmpty ? "Unavailable" : hotkeyLabel
        for (item, row) in [(recoveryItem, recoveryRow), (notificationsItem, notificationsRow),
                            (shortcutItem, shortcutRow), (loginItem, loginRow)] {
            item.isEnabled = state.pending == nil
            row.enabled = item.isEnabled
        }
        turnOffQuitItem.isEnabled = state.ownsSession && state.pending == nil
        turnOffQuitRow.enabled = turnOffQuitItem.isEnabled
        turnOffQuitRow.subtitle = state.ownsSession ? "Restore normal sleep first" : "No app-owned session is active"
        quitItem.isEnabled = state.pending == nil
        quitRow.enabled = quitItem.isEnabled
    }

    func installStatusCard() {
        let view = WorkWindowCard(model: cardModel,
                                  onToggle: { [weak self] in self?.toggle() },
                                  onDurationChange: { [weak self] in self?.setDuration($0) },
                                  onCheckSetup: { [weak self] in self?.checkSetup() })
            .environment(\.colorScheme, .dark)
        let host = ResizingCardHost(rootView: view)
        host.observe(cardModel)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        cardItem.view = host
        menu.addItem(cardItem)
    }

    func updateStatusCard() {
        cardModel.state = state
    }

    @objc func toggle() {
        guard state.pending == nil else { return }
        switch state.phase {
        case .off:
            performMutation(arguments: ["on"], pending: .turningOn, expected: .ownedOn)
        case .ownedOn:
            performMutation(arguments: ["off"], pending: .turningOff, expected: .off)
        case .externalOn:
            state.commandError = "Another tool owns this sleep hold. Closed-Lid Awake left it unchanged."
            applyState()
            showHUD(text: state.commandError!, symbol: "person.crop.circle.badge.exclamationmark")
        case .unknown:
            state.commandError = "Awake state is unknown. Check setup before changing it."
            applyState()
            showHUD(text: state.commandError!, symbol: "questionmark.diamond.fill")
        }
    }

    func performMutation(arguments: [String], pending: PendingAction, expected: SessionPhase,
                         completion: (() -> Void)? = nil) {
        guard state.pending == nil else { return }
        state.pending = pending
        state.commandError = nil
        applyState()
        let revision = revisionGate.issue()
        mutationQueue.async {
            let command = self.runner.run(executable: vibecafPath, arguments: arguments, timeout: 30)
            let verification = self.runner.run(executable: vibecafPath,
                                               arguments: ["status", "--json"], timeout: 5)
            let resolved = StateReconciler.afterCommand(command, verification: verification) { $0.phase == expected }
            DispatchQueue.main.async {
                guard self.revisionGate.accepts(revision) else { return }
                self.state = resolved
                self.applyState()
                if let error = resolved.commandError {
                    self.showHUD(text: error, symbol: "exclamationmark.triangle.fill")
                } else {
                    let on = resolved.phase == .ownedOn
                    self.showHUD(text: on ? "Work window on — verified" : "Work window off — verified",
                                 symbol: on ? "cup.and.saucer.fill" : "moon.zzz.fill")
                    completion?()
                }
            }
        }
    }

    // On a notched display the status item can end up hidden behind the notch
    // with no way to move it, so the hotkey needs its own visible confirmation.
    func showHUD(text: String, symbol: String) {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 15, weight: .medium)
        field.textColor = .labelColor
        field.maximumNumberOfLines = 3
        field.frame.size = NSSize(width: min(360, max(180, field.intrinsicContentSize.width)), height: 46)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        iconView.contentTintColor = .labelColor
        iconView.frame = NSRect(x: 22, y: 20, width: 26, height: 26)

        let w = field.frame.width + 80, h: CGFloat = 82
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
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                p.close()
                if self.hud === p { self.hud = nil }
                return
            }
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
        if hotKeyHandlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.toggle() }
                return noErr
            }, 1, &spec, nil, &hotKeyHandlerRef)
        }
        if let existing = hotKeyRef { UnregisterEventHotKey(existing); hotKeyRef = nil }

        let d = UserDefaults.standard
        let key = d.object(forKey: "HotkeyKeyCode") as? Int ?? kVK_ANSI_A
        if let modifiers = d.object(forKey: "HotkeyModifiers") as? Int, modifiers == 0 {
            hotkeyLabel = "Off"
            applyState()
            return
        }
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
        applyState()
    }

    @objc func configureShortcut() {
        let choices: [(String, Int)] = [
            ("Control–Option–A", 12),
            ("Control–Option–Command–A", 13),
            ("Control–Shift–A", 10),
            ("Off", 0),
        ]
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        popup.addItems(withTitles: choices.map(\.0))
        let current = UserDefaults.standard.object(forKey: "HotkeyModifiers") as? Int ?? 12
        popup.selectItem(at: choices.firstIndex(where: { $0.1 == current }) ?? 0)
        let alert = NSAlert()
        alert.messageText = "Keyboard shortcut"
        alert.informativeText = "Choose the global shortcut for the main work-window control."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.set(choices[popup.indexOfSelectedItem].1, forKey: "HotkeyModifiers")
        registerHotkey()
    }

    func performSetting(arguments: [String], verify: @escaping (State) -> Bool) {
        guard state.pending == nil else { return }
        state.pending = .saving
        state.commandError = nil
        applyState()
        let revision = revisionGate.issue()
        mutationQueue.async {
            let command = self.runner.run(executable: vibecafPath, arguments: arguments, timeout: 10)
            let verification = self.runner.run(executable: vibecafPath,
                                               arguments: ["status", "--json"], timeout: 5)
            let resolved = StateReconciler.afterCommand(command, verification: verification, accepts: verify)
            DispatchQueue.main.async {
                guard self.revisionGate.accepts(revision) else { return }
                self.state = resolved
                self.applyState()
            }
        }
    }

    func setDuration(_ seconds: Int) {
        guard SessionDuration.presets.contains(seconds) else { return }
        performSetting(arguments: ["config", "set", "duration", "\(seconds)"]) {
            $0.selectedDuration == seconds
        }
    }

    @objc func toggleRecovery() {
        let target = !state.networkRecovery
        performSetting(arguments: ["config", "set", "recovery", target ? "on" : "off"]) {
            $0.networkRecovery == target
        }
    }

    @objc func toggleNotifications() {
        let target = !state.agentNotifications
        performSetting(arguments: ["config", "set", "notifications", target ? "on" : "off"]) {
            $0.agentNotifications == target
        }
    }

    @objc func checkSetup() {
        DispatchQueue.global(qos: .utility).async {
            let result = self.runner.run(executable: vibecafPath, arguments: ["doctor"], timeout: 15)
            let text = result.succeeded ? result.stdoutText : result.failureDescription
            DispatchQueue.main.async { self.showDiagnostics(text) }
        }
    }

    func showDiagnostics(_ text: String) {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = text.isEmpty ? "No diagnostic output was returned." : text
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        let alert = NSAlert()
        alert.messageText = "Setup diagnostics"
        alert.informativeText = "This check is read-only. Select the text to copy it."
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func openNetLog() {
        DispatchQueue.global(qos: .utility).async {
            let result = self.runner.run(executable: vibecafPath, arguments: ["netlog", "--path"], timeout: 5)
            let path = result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if result.succeeded && path.hasPrefix("/") && FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } else {
                    self.showDiagnostics(result.succeeded ? "No network log has been recorded yet." : result.failureDescription)
                }
            }
        }
    }

    @objc func toggleAuto() {
        guard FileManager.default.fileExists(atPath: agentPlist) else {
            state.commandError = "Turn on ‘Show in menu bar at login’ first."
            applyState()
            return
        }
        let v = !UserDefaults.standard.bool(forKey: kAutoEnable)
        UserDefaults.standard.set(v, forKey: kAutoEnable)
        applyState()
    }

    @objc func toggleLogin() {
        let fm = FileManager.default
        if fm.fileExists(atPath: agentPlist) {
            do {
                try fm.removeItem(atPath: agentPlist)
                UserDefaults.standard.set(false, forKey: kAutoEnable)
            } catch {
                state.commandError = "Could not disable login launch: \(error.localizedDescription)"
            }
        } else {
            guard let exe = Bundle.main.executablePath, !exe.isEmpty else {
                state.commandError = "The app executable path is unavailable."
                applyState()
                return
            }
            let plist: [String: Any] = [
                "Label": agentLabel,
                "ProgramArguments": [exe],
                "EnvironmentVariables": ["CLA_LAUNCHED_AT_LOGIN": "1"],
                "RunAtLoad": true,
                "KeepAlive": false,
                "LimitLoadToSessionType": "Aqua",
            ]
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                try fm.createDirectory(atPath: (agentPlist as NSString).deletingLastPathComponent,
                                       withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: agentPlist), options: .atomic)
            } catch {
                state.commandError = "Could not enable login launch: \(error.localizedDescription)"
            }
        }
        applyState()
    }

    @objc func openUpdates() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ProofOfReach/ClosedLidAwake/releases/latest")!)
    }

    @objc func openSupport() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ProofOfReach/ClosedLidAwake/issues/new")!)
    }

    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
        let alert = NSAlert()
        alert.messageText = "Closed-Lid Awake \(version)"
        alert.informativeText = "A manual, time-bounded closed-lid work window with visible recovery."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func turnOffAndQuit() {
        guard state.ownsSession else { return }
        performMutation(arguments: ["off"], pending: .turningOff, expected: .off) {
            NSApp.terminate(nil)
        }
    }
}

#if CARD_PREVIEW
let previewApp = NSApplication.shared
previewApp.setActivationPolicy(.regular)
private let previewScenario = ProcessInfo.processInfo.environment["VIBECAF_CARD_PREVIEW_SCENARIO"] ?? "on"
private var previewState: State = {
    let deadline = Date().addingTimeInterval(5 * 3_600 + 42 * 60).timeIntervalSince1970
    var state = State(phase: .ownedOn, sessionID: "preview", startedAt: Date().timeIntervalSince1970,
                      deadline: deadline, remainingSeconds: 20_520, durationSeconds: 21_600,
                      powerSource: "AC", batteryPercent: 100, thermal: "nominal",
                      guardRunning: true, guardianRunning: true, recoveryReady: true,
                      networkState: "online", networkDetail: "Wi-Fi online", networkRecovery: true,
                      agents: AgentSummary(
                        claude: AgentCounts(working: 2, quiet: 1, finished: 0),
                        codex: AgentCounts(working: 3, quiet: 0, finished: 1)),
                      goals: GoalCounts(active: 4, stalled: 1, completed: 0, failed: 0),
                      observedAt: Date().timeIntervalSince1970)
    switch previewScenario {
    case "off":
        state.phase = .off; state.sessionID = nil; state.deadline = nil; state.remainingSeconds = nil
        state.recoveryReady = false; state.agents = AgentSummary(claude: .zero, codex: .zero); state.goals = .zero
    case "external":
        state.phase = .externalOn; state.sessionID = nil; state.deadline = nil; state.remainingSeconds = nil
        state.recoveryReady = false
    case "unknown":
        state = .unavailable("The helper status could not be verified.")
    case "error":
        state.commandError = "Authorization was canceled. Awake mode was not changed. Run Check setup for recovery steps."
    case "pending":
        state.phase = .off; state.pending = .turningOn
    case "battery":
        state.powerSource = "Battery"; state.batteryPercent = 24; state.thermal = "elevated"
        state.networkState = "offline"; state.networkDetail = "Wi-Fi has no route"
        state.issues = ["Recovery authorization is unavailable.", "Thermal helper is missing."]
        state.recoveryReady = false
    default: break
    }
    return state
}()
private let previewExpanded = ProcessInfo.processInfo.environment["VIBECAF_CARD_PREVIEW_EXPANDED"] == "1"
private let previewCardModel: WorkWindowCardModel = {
    let model = WorkWindowCardModel(state: previewState)
    model.activityExpanded = previewExpanded
    return model
}()
private let previewRows: [PanelRowModel] = [
    PanelRowModel(symbol: "gearshape.fill", title: "Settings", subtitle: "Session · startup · diagnostics", expanded: previewExpanded),
    PanelRowModel(symbol: "wifi", title: "Network monitoring", subtitle: "Read-only checks · repair guidance only", checked: previewState.networkRecovery, nested: true),
    PanelRowModel(symbol: "bell", title: "Notify when agent work changes", checked: previewState.agentNotifications, nested: true),
    PanelRowModel(symbol: "menubar.rectangle", title: "Show in menu bar at login", checked: false, nested: true),
    PanelRowModel(symbol: "stethoscope", title: "Check setup", subtitle: "Copyable, read-only diagnostics", nested: true),
    PanelRowModel(symbol: "power", title: "Turn off and quit", subtitle: "Restore normal sleep first"),
    PanelRowModel(symbol: "xmark.square.fill", title: "Quit menu bar app", shortcut: "⌘Q", slice: .bottom),
]
previewRows[previewExpanded ? 4 : 0].highlighted = true
private let previewPanel = VStack(spacing: 0) {
    WorkWindowCard(model: previewCardModel, onToggle: {}, onDurationChange: { _ in }, onCheckSetup: {})
    PanelDivider()
    PanelRow(model: previewRows[0])
    if previewExpanded {
        PanelLabel(text: "Session")
        PanelRow(model: previewRows[1])
        PanelRow(model: previewRows[2])
        PanelLabel(text: "Startup")
        PanelRow(model: previewRows[3])
        PanelLabel(text: "Diagnostics")
        PanelRow(model: previewRows[4])
        Color.clear.frame(width: Ink.panelWidth, height: 6).panelSlice(.middle)
    }
    PanelDivider()
    PanelRow(model: previewRows[5])
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
#elseif !UI_UNIT_TEST
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#endif
