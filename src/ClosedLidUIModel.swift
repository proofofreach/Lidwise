import Foundation
import Darwin

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

struct CommandResult: Equatable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32?
    let timedOut: Bool
    let launchError: String?

    var succeeded: Bool { !timedOut && launchError == nil && exitCode == 0 }
    var stdoutText: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }

    var failureDescription: String {
        if timedOut { return "The helper did not respond in time." }
        if let launchError { return "The helper could not start: \(launchError)" }
        let detail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { return detail }
        if let exitCode { return "The helper exited with status \(exitCode)." }
        return "The helper failed."
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

protocol CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
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

struct ProcessRunner: CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { return failure("Cannot create output pipe") }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1]); return failure("Cannot create error pipe")
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], STDERR_FILENO)
        for fd in outPipe + errPipe { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        // Establish a private child process group atomically at spawn. Calling
        // setpgid after Process.run races exec and can silently fail.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        let strings = ([executable] + arguments).map { strdup($0) }
        defer { for string in strings { free(string) } }
        var argv = strings + [nil]
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, &argv, environ)
        close(outPipe[1]); close(errPipe[1])
        guard spawned == 0 else {
            close(outPipe[0]); close(errPipe[0])
            return failure(String(cString: strerror(spawned)))
        }
        var outFD = outPipe[0], errFD = errPipe[0]
        _ = fcntl(outFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(errFD, F_SETFL, O_NONBLOCK)
        var stdout = Data(), stderr = Data()
        var status: Int32 = 0
        var exited = false
        var timedOut = false
        var overflow = false
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        let outputLimit = 4 * 1024 * 1024

        func drain(_ descriptor: inout Int32, into data: inout Data) {
            guard descriptor >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            // Bound each pass so a noisy child cannot starve the deadline check.
            for _ in 0..<32 {
                let count = read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    if data.count + count <= outputLimit { data.append(buffer, count: count) }
                    else { overflow = true }
                } else if count == 0 {
                    close(descriptor); descriptor = -1; return
                } else {
                    if errno != EAGAIN && errno != EINTR { close(descriptor); descriptor = -1 }
                    return
                }
            }
        }
        while true {
            drain(&outFD, into: &stdout); drain(&errFD, into: &stderr)
            if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
            if exited && outFD < 0 && errFD < 0 { break }
            if overflow || ProcessInfo.processInfo.systemUptime >= deadline {
                timedOut = !overflow
                // The deadline covers both the parent and inherited pipe handles.
                _ = kill(-pid, SIGTERM)
                let grace = ProcessInfo.processInfo.systemUptime + 0.25
                while ProcessInfo.processInfo.systemUptime < grace {
                    drain(&outFD, into: &stdout); drain(&errFD, into: &stderr)
                    if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
                    usleep(10_000)
                }
                _ = kill(-pid, SIGKILL)
                if !exited { exited = waitpid(pid, &status, WNOHANG) == pid }
                break
            }
            var descriptors = [pollfd(fd: outFD, events: Int16(POLLIN | POLLHUP), revents: 0),
                               pollfd(fd: errFD, events: Int16(POLLIN | POLLHUP), revents: 0)]
            _ = poll(&descriptors, nfds_t(descriptors.count), 10)
        }
        if outFD >= 0 { close(outFD) }
        if errFD >= 0 { close(errFD) }
        if !exited {
            // Reap without holding the UI operation open if kernel exit is delayed.
            let child = pid
            DispatchQueue.global(qos: .utility).async { var ignored: Int32 = 0; _ = waitpid(child, &ignored, 0) }
        }
        let exitCode: Int32? = exited ? ((status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)) : nil
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode,
                             timedOut: timedOut,
                             launchError: overflow ? "The helper exceeded the output limit." : nil)
    }

    private func failure(_ message: String) -> CommandResult {
        CommandResult(stdout: Data(), stderr: Data(), exitCode: nil, timedOut: false, launchError: message)
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
