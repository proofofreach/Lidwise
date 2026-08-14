// Closed-Lid Awake — menu bar control for ~/.local/bin/vibecaf
import AppKit
import Carbon.HIToolbox

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

struct State {
    var on = false
    var power = ""
    var onBattery = false
    var net = ""
    var netOK = false
    var watchdog = false
    var guarded = false
    var autoOff = ""
    var floor = ""
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
        if line.hasPrefix("Wi-Fi watchdog pid:") { s.watchdog = !line.contains("none") }
        if line.hasPrefix("Guard pid:") { s.guarded = !line.contains("none") }
        if line.hasPrefix("Auto-off in:") { s.autoOff = line.replacingOccurrences(of: "Auto-off in: ", with: "") }
        if line.hasPrefix("Battery floor:") { s.floor = line.replacingOccurrences(of: "Battery floor: ", with: "") }
    }
    return s
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

    let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let powerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let netItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let netLogItem = NSMenuItem(title: "Open Wi-Fi watchdog log", action: #selector(openNetLog), keyEquivalent: "")
    let toggleItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "a")
    let hotkeyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let placementItem = NSMenuItem(title: "Move icon out of the notch", action: #selector(fixPlacement), keyEquivalent: "")
    let autoItem = NSMenuItem(title: "Enable awake mode at login", action: #selector(toggleAuto), keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Show in menu bar at login", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        for i in [headerItem, powerItem, netItem, hotkeyItem] { i.isEnabled = false }
        menu.addItem(headerItem)
        menu.addItem(powerItem)
        menu.addItem(netItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(hotkeyItem)
        menu.addItem(.separator())
        for i in [autoItem, loginItem, netLogItem, placementItem] { i.target = self; menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        toggleItem.target = self

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
    func menuWillOpen(_ menu: NSMenu) {
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

        placementItem.title = iconHidden
            ? "⚠︎ Icon is behind the notch — try to move it"
            : "Move icon out of the notch"

        if state.on {
            // The dead-man deadline is the single most useful thing to show while
            // it's running: it answers "did I leave this on?" without a terminal.
            headerItem.title = state.autoOff.isEmpty || state.autoOff == "n/a"
                ? "Awake mode: ON — lid can stay closed"
                : "Awake mode: ON — auto-off in \(state.autoOff)"
        } else {
            headerItem.title = "Awake mode: OFF"
        }
        // On battery the guard is the reason this is a warning and not a threat.
        powerItem.title = state.on && state.onBattery
            ? "\(state.power)  ⚠︎ draining — auto-off at \(state.floor.isEmpty ? "the battery floor" : state.floor)"
            : state.power
        let wd = state.watchdog ? "watchdog on" : "watchdog off"
        let gd = state.guarded ? "guard on" : "⚠︎ guard off"
        netItem.title = "Network: \(state.net)\(state.on ? " · \(wd) · \(gd)" : "")"
        toggleItem.title = state.on ? "Turn Off" : "Turn On"
        hotkeyItem.title = "Hotkey: \(hotkeyLabel)"
        autoItem.state = UserDefaults.standard.bool(forKey: kAutoEnable) ? .on : .off
        loginItem.state = FileManager.default.fileExists(atPath: agentPlist) ? .on : .off
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
