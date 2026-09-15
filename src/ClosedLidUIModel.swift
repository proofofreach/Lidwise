import Foundation

enum SessionPhase: String, Codable {
    case off
    case ownedOn = "owned-on"
    case externalOn = "external-on"
    case unknown
}

enum PendingAction: Equatable {
    case turningOn
    case turningOff
    case saving

    var label: String {
        switch self {
        case .turningOn: return "Turning on…"
        case .turningOff: return "Turning off…"
        case .saving: return "Saving…"
        }
    }
}

struct AgentCounts: Codable, Equatable {
    var working: Int
    var quiet: Int
    var finished: Int

    static let zero = AgentCounts(working: 0, quiet: 0, finished: 0)

    var isEmpty: Bool { working == 0 && quiet == 0 && finished == 0 }

    var detail: String {
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if quiet > 0 { parts.append("\(quiet) quiet") }
        if finished > 0 { parts.append("\(finished) finished") }
        return parts.joined(separator: " · ")
    }
}

struct AgentSummary: Codable, Equatable {
    var claude: AgentCounts
    var codex: AgentCounts
}

struct GoalCounts: Codable, Equatable {
    var active: Int
    var stalled: Int
    var completed: Int
    var failed: Int

    static let zero = GoalCounts(active: 0, stalled: 0, completed: 0, failed: 0)
    var isEmpty: Bool { active == 0 && stalled == 0 && completed == 0 && failed == 0 }

    var detail: String {
        var parts: [String] = []
        if active > 0 { parts.append("\(active) active") }
        if stalled > 0 { parts.append("\(stalled) stalled") }
        if completed > 0 { parts.append("\(completed) completed") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }
}

struct State: Codable, Equatable {
    var schemaVersion: Int
    var phase: SessionPhase
    var sessionID: String?
    var startedAt: TimeInterval?
    var deadline: TimeInterval?
    var remainingSeconds: Int?
    var durationSeconds: Int
    var defaultDurationSeconds: Int?
    var batteryFloor: Int
    var powerSource: String?
    var batteryPercent: Int?
    var thermal: String?
    var thermalLabel: String {
        switch thermal {
        case "nominal": return "Normal"
        case "fair": return "Warm"
        case "serious": return "High"
        case "critical": return "Critical"
        default: return "Temperature unknown"
        }
    }
    var guardRunning: Bool
    var guardianRunning: Bool
    var recoveryReady: Bool
    var issues: [String]
    var networkState: String
    var networkDetail: String
    var networkRecovery: Bool
    var networkRecoveryAvailable: Bool?
    var agentNotifications: Bool
    var agents: AgentSummary
    var goals: GoalCounts
    var observedAt: TimeInterval

    var pending: PendingAction? = nil
    var commandError: String? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case phase
        case sessionID = "session_id"
        case startedAt = "started_at"
        case deadline
        case remainingSeconds = "remaining_seconds"
        case durationSeconds = "duration_seconds"
        case defaultDurationSeconds = "default_duration_seconds"
        case batteryFloor = "battery_floor"
        case powerSource = "power_source"
        case batteryPercent = "battery_percent"
        case thermal
        case guardRunning = "guard_running"
        case guardianRunning = "guardian_running"
        case recoveryReady = "recovery_ready"
        case issues
        case networkState = "network_state"
        case networkDetail = "network_detail"
        case networkRecovery = "network_recovery"
        case networkRecoveryAvailable = "network_recovery_available"
        case agentNotifications = "agent_notifications"
        case agents, goals
        case observedAt = "observed_at"
    }

    init(schemaVersion: Int = 1, phase: SessionPhase = .unknown,
         sessionID: String? = nil, startedAt: TimeInterval? = nil,
         deadline: TimeInterval? = nil, remainingSeconds: Int? = nil,
         durationSeconds: Int = 21_600, defaultDurationSeconds: Int? = nil, batteryFloor: Int = 20,
         powerSource: String? = nil, batteryPercent: Int? = nil,
         thermal: String? = nil, guardRunning: Bool = false,
         guardianRunning: Bool = false, recoveryReady: Bool = false,
         issues: [String] = [], networkState: String = "unknown",
         networkDetail: String = "Not checked", networkRecovery: Bool = true,
         networkRecoveryAvailable: Bool? = nil,
         agentNotifications: Bool = false,
         agents: AgentSummary = AgentSummary(claude: .zero, codex: .zero),
         goals: GoalCounts = .zero, observedAt: TimeInterval = 0,
         pending: PendingAction? = nil, commandError: String? = nil) {
        self.schemaVersion = schemaVersion
        self.phase = phase
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.deadline = deadline
        self.remainingSeconds = remainingSeconds
        self.durationSeconds = durationSeconds
        self.defaultDurationSeconds = defaultDurationSeconds
        self.batteryFloor = batteryFloor
        self.powerSource = powerSource
        self.batteryPercent = batteryPercent
        self.thermal = thermal
        self.guardRunning = guardRunning
        self.guardianRunning = guardianRunning
        self.recoveryReady = recoveryReady
        self.issues = issues
        self.networkState = networkState
        self.networkDetail = networkDetail
        self.networkRecovery = networkRecovery
        self.networkRecoveryAvailable = networkRecoveryAvailable
        self.agentNotifications = agentNotifications
        self.agents = agents
        self.goals = goals
        self.observedAt = observedAt
        self.pending = pending
        self.commandError = commandError
    }

    static func unavailable(_ message: String? = nil) -> State {
        State(phase: .unknown, issues: message.map { [$0] } ?? [], commandError: message)
    }

    var selectedDuration: Int { defaultDurationSeconds ?? durationSeconds }

    var ownsSession: Bool { phase == .ownedOn }
    var isExternallyHeld: Bool { phase == .externalOn }
}

enum StatusParseError: LocalizedError, Equatable {
    case malformedJSON
    case missingKey(String)
    case unsupportedSchema(Int)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .malformedJSON: return "The helper returned malformed status data."
        case .missingKey(let key): return "The helper status is missing ‘\(key)’."
        case .unsupportedSchema(let version): return "The helper uses unsupported status schema \(version)."
        case .invalidPayload(let detail): return "The helper returned invalid status data: \(detail)"
        }
    }
}

enum StatusParser {
    static let requiredKeys: Set<String> = [
        "schema_version", "phase", "session_id", "started_at", "deadline",
        "remaining_seconds", "duration_seconds", "battery_floor", "power_source",
        "battery_percent", "thermal", "guard_running", "guardian_running",
        "recovery_ready", "issues", "network_state", "network_detail",
        "network_recovery", "agent_notifications", "agents", "goals", "observed_at"
    ]

    static func parse(_ data: Data) throws -> State {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw StatusParseError.malformedJSON
        }
        for key in requiredKeys where dictionary[key] == nil {
            throw StatusParseError.missingKey(key)
        }
        guard let schema = dictionary["schema_version"] as? Int else {
            throw StatusParseError.invalidPayload("schema_version is not an integer")
        }
        guard schema == 1 else { throw StatusParseError.unsupportedSchema(schema) }
        do {
            var state = try JSONDecoder().decode(State.self, from: data)
            state.pending = nil
            state.commandError = nil
            return state
        } catch {
            throw StatusParseError.invalidPayload(error.localizedDescription)
        }
    }
}

// Every mutating command is reconciled with observed state, including failures.
// A command can change power before returning an error; the old UI state is never evidence.
enum StateReconciler {
    static func afterCommand(_ command: CommandResult, verification: CommandResult,
                             accepts: (State) -> Bool) -> State {
        var observed: State
        if verification.succeeded {
            do { observed = try StatusParser.parse(verification.stdout) }
            catch { return .unavailable(error.localizedDescription) }
        } else {
            return .unavailable(verification.failureDescription)
        }
        if !command.succeeded { observed.commandError = command.failureDescription }
        else if !accepts(observed) { observed.commandError = "The requested change was not verified. Current state: \(observed.phase.rawValue)." }
        return observed
    }
}

// Optional observation has its own queue and never waits in the power-command path.
final class ActivityRefreshWorker {
    private let runner: CommandRunning
    private let queue = DispatchQueue(label: "app.closedlidawake.activity", qos: .utility)
    private let lock = NSLock()
    private var pending = false
    private var latestCompletion: (() -> Void)?

    init(runner: CommandRunning) { self.runner = runner }

    func refreshIfNeeded(ownedSession: Bool, executable: String, completion: @escaping () -> Void) {
        guard !ownedSession else { return } // An owned session already has an observer.
        lock.lock()
        latestCompletion = completion
        guard !pending else { lock.unlock(); return }
        pending = true
        lock.unlock()
        queue.async {
            _ = self.runner.run(executable: executable, arguments: ["__observation_once"], timeout: 20)
            self.lock.lock()
            self.pending = false
            let completion = self.latestCompletion
            self.latestCompletion = nil
            self.lock.unlock()
            completion?()
        }
    }
}

final class RevisionGate {
    private let lock = NSLock()
    private var latest = 0

    func issue() -> Int {
        lock.lock(); defer { lock.unlock() }
        latest += 1
        return latest
    }

    func accepts(_ revision: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return revision == latest
    }
}

enum SessionDuration {
    static let presets = [1_800, 3_600, 7_200, 21_600]

    static func label(for seconds: Int) -> String {
        switch seconds {
        case 1_800: return "30m"
        case 3_600: return "1h"
        case 7_200: return "2h"
        case 21_600: return "6h"
        default: return "\(seconds / 60)m"
        }
    }
}
