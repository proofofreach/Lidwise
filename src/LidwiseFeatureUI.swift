import AppKit
import SwiftUI
import Combine

private enum FeatureTone {
    static let accent = Color(red: 0.39, green: 0.55, blue: 1.0)
    static let mint = Color(red: 0.39, green: 0.85, blue: 0.69)
    static let amber = Color(red: 0.95, green: 0.69, blue: 0.32)
    static let coral = Color(red: 1.0, green: 0.46, blue: 0.48)
}

enum VerificationExpectation: String, Codable, CaseIterable, Identifiable {
    case awake
    case sleep

    var id: String { rawValue }
    var label: String { self == .awake ? "Stay awake" : "Go to sleep" }
}

enum VerificationOutcome: String, Codable {
    case passed
    case failed
    case inconclusive
}

struct VerificationPayload: Codable, Equatable {
    var schemaVersion: Int
    var expectation: VerificationExpectation
    var result: VerificationOutcome
    var summary: String
    var durationSeconds: Double
    var closedLidSeconds: Double
    var sleepSeconds: Double
    var maxSampleGap: Double
    var model: String
    var osVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case expectation, result, summary
        case durationSeconds = "duration_seconds"
        case closedLidSeconds = "closed_lid_seconds"
        case sleepSeconds = "sleep_seconds"
        case maxSampleGap = "max_sample_gap"
        case model
        case osVersion = "os_version"
    }

    var report: String {
        """
        Result: \(result.rawValue.capitalized)
        Expected: \(expectation.label)
        Summary: \(summary)
        Duration: \(Self.seconds(durationSeconds))
        Lid closed: \(Self.seconds(closedLidSeconds))
        Sleep observed: \(Self.seconds(sleepSeconds))
        Largest sample gap: \(Self.seconds(maxSampleGap))
        Mac: \(model)
        macOS: \(osVersion)
        """
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f seconds", value)
    }
}

struct HookProviderStatus: Codable, Equatable {
    var supported: Bool
    var configured: Bool
    var events: [String]
    var reason: String?
}

struct HookStatusPayload: Codable, Equatable {
    var schemaVersion: Int
    var claude: HookProviderStatus
    var codex: HookProviderStatus

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case claude, codex
    }
}

enum LidwiseFeatureParser {
    static func verification(_ data: Data) throws -> VerificationPayload {
        let payload: VerificationPayload = try decode(data, name: "verification")
        guard payload.schemaVersion == 1 else { throw StatusParseError.unsupportedSchema(payload.schemaVersion) }
        return payload
    }

    static func hookStatus(_ data: Data) throws -> HookStatusPayload {
        let payload: HookStatusPayload = try decode(data, name: "hook status")
        guard payload.schemaVersion == 1 else { throw StatusParseError.unsupportedSchema(payload.schemaVersion) }
        return payload
    }

    static func prettyJSON(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8) else {
            return String(data: data, encoding: .utf8) ?? "No preview was returned."
        }
        return text
    }

    private static func decode<T: Decodable>(_ data: Data, name: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw StatusParseError.invalidPayload("\(name): \(error.localizedDescription)") }
    }
}

final class VerificationWorker {
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "app.lidwiseawake.verification", qos: .utility)

    init(runner: CommandRunning) { self.runner = runner }

    func run(executable: String, expectation: VerificationExpectation, seconds: Int,
             completion: @escaping (Result<VerificationPayload, Error>) -> Void) {
        let boundedSeconds = min(120, max(15, seconds))
        queue.async {
            let command = self.runner.run(
                executable: executable,
                arguments: ["verify", "--expect", expectation.rawValue, "--seconds", "\(boundedSeconds)", "--json"],
                timeout: TimeInterval(boundedSeconds + 20)
            )
            guard command.succeeded else {
                completion(.failure(NSError(
                    domain: "app.lidwiseawake", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: command.failureDescription]
                )))
                return
            }
            do {
                guard !command.stdout.isEmpty else {
                    throw NSError(domain: "app.lidwiseawake", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "No verification result was returned."])
                }
                completion(.success(try LidwiseFeatureParser.verification(command.stdout)))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

final class HistoryWorker {
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "app.lidwiseawake.history", qos: .utility)

    init(runner: CommandRunning) { self.runner = runner }

    func load(executable: String, completion: @escaping (Result<[SessionRecord], Error>) -> Void) {
        queue.async {
            let command = self.runner.run(executable: executable, arguments: ["history", "--json"], timeout: 5)
            guard command.succeeded else {
                completion(.failure(NSError(domain: "app.lidwiseawake", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: command.failureDescription])))
                return
            }
            do { completion(.success(try FeaturePayloadParser.history(command.stdout).sessions)) }
            catch { completion(.failure(error)) }
        }
    }
}

final class AgentIntegrationWorker {
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "app.lidwiseawake.hooks", qos: .utility)

    init(runner: CommandRunning) { self.runner = runner }

    func status(executable: String, completion: @escaping (Result<HookStatusPayload, Error>) -> Void) {
        queue.async { completion(self.readStatus(executable: executable)) }
    }

    func preview(executable: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let command = self.runner.run(executable: executable,
                                          arguments: ["hooks", "preview", "claude", "--json"], timeout: 5)
            if command.succeeded {
                completion(.success(LidwiseFeatureParser.prettyJSON(command.stdout)))
            } else {
                completion(.failure(NSError(domain: "app.lidwiseawake", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: command.failureDescription])))
            }
        }
    }

    func configure(executable: String, install: Bool,
                   completion: @escaping (Result<HookStatusPayload, Error>) -> Void) {
        queue.async {
            let command = self.runner.run(executable: executable,
                                          arguments: ["hooks", install ? "install" : "remove", "claude"], timeout: 10)
            guard command.succeeded else {
                completion(.failure(NSError(domain: "app.lidwiseawake", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: command.failureDescription])))
                return
            }
            completion(self.readStatus(executable: executable))
        }
    }

    private func readStatus(executable: String) -> Result<HookStatusPayload, Error> {
        let command = runner.run(executable: executable,
                                 arguments: ["hooks", "status", "--json"], timeout: 5)
        guard command.succeeded else {
            return .failure(NSError(domain: "app.lidwiseawake", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: command.failureDescription]))
        }
        do { return .success(try LidwiseFeatureParser.hookStatus(command.stdout)) }
        catch { return .failure(error) }
    }
}

final class GuidedVerificationViewModel: ObservableObject {
    @Published var expectation: VerificationExpectation = .awake
    @Published var seconds = 60
    @Published var running = false
    @Published var result: VerificationPayload?
    @Published var error: String?
}

struct GuidedVerificationView: View {
    @ObservedObject var model: GuidedVerificationViewModel
    let start: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Test closed-lid behavior")
                    .font(.title2.weight(.semibold))
                Text("Place the Mac on a firm, ventilated surface. Start the test, close the lid, wait, then reopen it. The test only measures behavior.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Expected behavior", selection: $model.expectation) {
                ForEach(VerificationExpectation.allCases) { expectation in
                    Text(expectation.label).tag(expectation)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.running)

            Stepper("Test for \(model.seconds) seconds", value: $model.seconds, in: 15...120, step: 15)
                .disabled(model.running)

            if model.running {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView()
                    Text("Measuring now. Keep the lid closed until the selected time has passed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Verification in progress")
            } else if let result = model.result {
                ResultBox(text: result.report, tone: result.result == .passed ? FeatureTone.mint : result.result == .failed ? FeatureTone.coral : FeatureTone.amber)
            } else if let error = model.error {
                ResultBox(text: error, tone: FeatureTone.coral)
            }

            Spacer(minLength: 0)
            HStack {
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let report = model.result?.report {
                    Button("Copy result") { copyToPasteboard(report) }
                }
                Button(model.result == nil ? "Start test" : "Run again", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.running)
            }
        }
        .padding(22)
        .frame(minWidth: 480, idealWidth: 500, minHeight: 390, idealHeight: 440)
    }
}

private struct ResultBox: View {
    let text: String
    let tone: Color

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(minHeight: 120, maxHeight: 190)
        .background(RoundedRectangle(cornerRadius: 10).fill(tone.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tone.opacity(0.45), lineWidth: 1))
    }
}

final class GuidedVerificationController {
    let model = GuidedVerificationViewModel()
    private let worker: VerificationWorker
    private let executable: String
    private lazy var panel: NSPanel = makePanel()

    init(runner: CommandRunning, executable: String) {
        worker = VerificationWorker(runner: runner)
        self.executable = executable
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Lidwise verification"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: GuidedVerificationView(
            model: model,
            start: { [weak self] in self?.start() },
            close: { [weak panel] in panel?.orderOut(nil) }
        ))
        return panel
    }

    private func start() {
        guard !model.running else { return }
        model.running = true
        model.result = nil
        model.error = nil
        worker.run(executable: executable, expectation: model.expectation, seconds: model.seconds) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.running = false
                switch result {
                case .success(let payload): self.model.result = payload
                case .failure(let error): self.model.error = error.localizedDescription
                }
            }
        }
    }
}

final class SessionHistoryViewModel: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var selection: String?
    @Published var loading = false
    @Published var error: String?
}

struct SessionHistoryView: View {
    @ObservedObject var model: SessionHistoryViewModel
    let reload: () -> Void
    let close: () -> Void

    private var selected: SessionRecord? {
        model.sessions.first { $0.sessionID == model.selection } ?? model.sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session history").font(.title2.weight(.semibold))
                    Text("Stored privately on this Mac. Up to 20 sessions.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button("Refresh", action: reload).disabled(model.loading)
            }

            if let error = model.error {
                Text(error).foregroundStyle(FeatureTone.coral).fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.sessions) { session in
                            Button {
                                model.selection = session.sessionID
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(SessionText.date(session.endedAt))
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                    Text(SessionText.reason(session.reason))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(model.selection == session.sessionID ? FeatureTone.accent.opacity(0.25) : Color.clear))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(SessionText.date(session.endedAt)), \(SessionText.reason(session.reason))")
                        }
                    }
                    .padding(5)
                }
                .frame(width: 210)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))

                if let session = selected {
                    ScrollView {
                        Text(SessionText.report(session))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button("Copy details") { copyToPasteboard(SessionText.report(session)) }
                            .padding(8)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No sessions").font(.headline)
                        Text("Recent sessions will appear here.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 300)

            HStack { Spacer(); Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 430, idealHeight: 470)
    }
}

enum SessionText {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func date(_ value: TimeInterval) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: value))
    }

    static func reason(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func report(_ session: SessionRecord) -> String {
        let endedLabel = session.restoration == .failed ? "Last restoration attempt" : "Ended"
        let endPowerLabel = session.restoration == .failed ? "Power at last attempt" : "Ending power"
        return """
        Started: \(date(session.startedAt))
        \(endedLabel): \(date(session.endedAt))
        Scheduled deadline: \(date(session.deadline))
        End reason: \(reason(session.reason))
        Sleep restoration: \(session.restoration.rawValue.capitalized)
        Starting power: \(power(session.powerStart, battery: session.batteryStart))
        \(endPowerLabel): \(power(session.powerEnd, battery: session.batteryEnd))
        Session ID: \(session.sessionID)
        """
    }

    private static func power(_ source: String?, battery: Int?) -> String {
        let sourceText = source ?? "Not measured"
        return battery.map { "\(sourceText), \($0)%" } ?? sourceText
    }
}

final class SessionHistoryController {
    let model = SessionHistoryViewModel()
    private let worker: HistoryWorker
    private let executable: String
    private lazy var panel: NSPanel = makePanel()

    init(runner: CommandRunning, executable: String) {
        worker = HistoryWorker(runner: runner)
        self.executable = executable
    }

    func show(seed: SessionRecord?) {
        if model.sessions.isEmpty, let seed {
            model.sessions = [seed]
            model.selection = seed.sessionID
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Lidwise session history"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SessionHistoryView(
            model: model,
            reload: { [weak self] in self?.reload() },
            close: { [weak panel] in panel?.orderOut(nil) }
        ))
        return panel
    }

    private func reload() {
        guard !model.loading else { return }
        model.loading = true
        model.error = nil
        worker.load(executable: executable) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.loading = false
                switch result {
                case .success(let sessions):
                    self.model.sessions = sessions
                    if !sessions.contains(where: { $0.sessionID == self.model.selection }) {
                        self.model.selection = sessions.first?.sessionID
                    }
                case .failure(let error): self.model.error = error.localizedDescription
                }
            }
        }
    }
}

final class AgentIntegrationViewModel: ObservableObject {
    @Published var status: HookStatusPayload?
    @Published var preview = ""
    @Published var loading = false
    @Published var error: String?
}

struct AgentIntegrationView: View {
    @ObservedObject var model: AgentIntegrationViewModel
    let refresh: () -> Void
    let preview: () -> Void
    let configure: (Bool) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Agent integrations").font(.title2.weight(.semibold))
                    Text("Lifecycle signals update activity only. They never change the power session.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.loading { ProgressView().controlSize(.small) }
            }

            provider("Claude Code", status: model.status?.claude)
            provider("Codex", status: model.status?.codex)

            if let error = model.error {
                Text(error).foregroundStyle(FeatureTone.coral).fixedSize(horizontal: false, vertical: true)
            }

            if !model.preview.isEmpty {
                ResultBox(text: model.preview, tone: FeatureTone.accent)
            } else if model.status?.claude.supported == true && model.status?.claude.configured == false {
                Text("Preview the exact configuration change before setup.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            HStack {
                Button("Close", action: close).keyboardShortcut(.cancelAction)
                Button("Refresh", action: refresh).disabled(model.loading)
                Spacer()
                Button("Preview Claude setup", action: preview)
                    .disabled(model.loading || model.status?.claude.supported == false)
                if let claude = model.status?.claude, claude.supported {
                    Button(claude.configured ? "Remove Claude setup" : "Set up Claude") {
                        configure(!claude.configured)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.loading || (!claude.configured && model.preview.isEmpty))
                }
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 470)
    }

    private func provider(_ name: String, status: HookProviderStatus?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status?.configured == true ? "checkmark.circle.fill" :
                    status?.supported == true ? "circle.dashed" : "minus.circle")
                .foregroundStyle(status?.configured == true ? FeatureTone.mint : status?.supported == true ? FeatureTone.amber : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).fontWeight(.semibold)
                Text(providerDetail(status)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
    }

    private func providerDetail(_ status: HookProviderStatus?) -> String {
        guard let status else { return model.loading ? "Checking…" : "Status unavailable" }
        if let reason = status.reason, !status.supported { return reason }
        let state = status.configured ? "Configured" : status.supported ? "Available" : "Unavailable"
        return status.events.isEmpty ? state : "\(state) · \(status.events.joined(separator: ", "))"
    }
}

final class AgentIntegrationController {
    let model = AgentIntegrationViewModel()
    private let worker: AgentIntegrationWorker
    private let executable: String
    private lazy var panel: NSPanel = makePanel()

    init(runner: CommandRunning, executable: String) {
        worker = AgentIntegrationWorker(runner: runner)
        self.executable = executable
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Lidwise agent integrations"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AgentIntegrationView(
            model: model,
            refresh: { [weak self] in self?.refresh() },
            preview: { [weak self] in self?.loadPreview() },
            configure: { [weak self] install in self?.configure(install: install) },
            close: { [weak panel] in panel?.orderOut(nil) }
        ))
        return panel
    }

    private func refresh() {
        guard !model.loading else { return }
        model.loading = true
        model.error = nil
        model.preview = ""
        worker.status(executable: executable) { [weak self] result in self?.finishStatus(result) }
    }

    private func loadPreview() {
        guard !model.loading else { return }
        model.loading = true
        model.error = nil
        worker.preview(executable: executable) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.loading = false
                switch result {
                case .success(let text): self.model.preview = text
                case .failure(let error): self.model.error = error.localizedDescription
                }
            }
        }
    }

    private func configure(install: Bool) {
        guard !model.loading else { return }
        model.loading = true
        model.error = nil
        worker.configure(executable: executable, install: install) { [weak self] result in self?.finishStatus(result) }
    }

    private func finishStatus(_ result: Result<HookStatusPayload, Error>) {
        DispatchQueue.main.async {
            self.model.loading = false
            switch result {
            case .success(let status): self.model.status = status
            case .failure(let error): self.model.error = error.localizedDescription
            }
        }
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
