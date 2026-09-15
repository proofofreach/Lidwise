import Foundation

@main
struct LidwiseUIModelTests {
    static var failures = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            fputs("FAIL: \(message)\n", stderr)
        }
    }

    static func statusJSON(phase: String = "off", extra: String = "") -> Data {
        Data("""
        {
          "schema_version": 1,
          "phase": "\(phase)",
          "session_id": null,
          "started_at": null,
          "deadline": null,
          "remaining_seconds": null,
          "duration_seconds": 21600,
          "battery_floor": 20,
          "power_source": "AC",
          "battery_percent": 100,
          "thermal": "nominal",
          "guard_running": false,
          "guardian_running": false,
          "recovery_ready": false,
          "issues": [],
          "network_state": "unknown",
          "network_detail": "Not checked",
          "network_recovery": true,
          "network_recovery_available": false,
          "agent_notifications": false,
          "agents": {
            "claude": {"working": 0, "quiet": 0, "finished": 0},
            "codex": {"working": 0, "quiet": 0, "finished": 0}
          },
          "goals": {"active": 0, "stalled": 0, "completed": 0, "failed": 0},
          "observed_at": 42\(extra)
        }
        """.utf8)
    }

    static func testStatusParsing() {
        do {
            let state = try StatusParser.parse(statusJSON(phase: "external-on"))
            check(state.phase == .externalOn, "external-on must remain distinct from off")
            check(state.networkRecovery, "saved network monitoring setting must decode")
            check(state.networkRecoveryAvailable == false, "automatic repair capability must decode separately")
            check(state.agents.claude.waiting == 0 && state.agents.claude.failed == 0,
                  "older agent payloads must decode additive attention counts as zero")
        } catch { check(false, "valid status failed: \(error)") }

        do {
            let state = try StatusParser.parse(statusJSON(phase: "unknown"))
            check(state.phase == .unknown, "unknown must remain explicit")
        } catch { check(false, "unknown status failed: \(error)") }

        do {
            var nullable = String(data: statusJSON(), encoding: .utf8)!
            nullable = nullable.replacingOccurrences(of: "\"power_source\": \"AC\"", with: "\"power_source\": null")
            nullable = nullable.replacingOccurrences(of: "\"thermal\": \"nominal\"", with: "\"thermal\": null")
            let state = try StatusParser.parse(Data(nullable.utf8))
            check(state.powerSource == nil && state.thermal == nil,
                  "unavailable sensor fields must accept explicit null")
        } catch { check(false, "nullable status fields failed: \(error)") }

        do {
            _ = try StatusParser.parse(Data("not json".utf8))
            check(false, "malformed JSON was accepted")
        } catch let error as StatusParseError {
            check(error == .malformedJSON, "malformed JSON reported the wrong error")
        } catch { check(false, "malformed JSON reported an unexpected error") }

        var missing = String(data: statusJSON(), encoding: .utf8)!
        missing = missing.replacingOccurrences(of: "\"deadline\": null,", with: "")
        do {
            _ = try StatusParser.parse(Data(missing.utf8))
            check(false, "missing nullable key was accepted")
        } catch let error as StatusParseError {
            check(error == .missingKey("deadline"), "missing key did not identify deadline")
        } catch { check(false, "missing key reported an unexpected error") }

        do {
            _ = try StatusParser.parse(statusJSON(phase: "surprise"))
            check(false, "unsupported phase was accepted")
        } catch { }
    }

    static func testFeaturePayloads() {
        let record = """
        {"session_id":"session-1","started_at":100,"ended_at":200,"deadline":220,
         "reason":"battery-floor","restoration":"failed","battery_start":52,"battery_end":20,
         "power_start":"Battery","power_end":"Battery"}
        """
        let extra = """
        ,"default_battery_floor":25,"require_ac":false,"default_require_ac":true,
        "can_extend":true,"last_session":\(record)
        """
        do {
            var json = String(data: statusJSON(phase: "owned-on", extra: extra), encoding: .utf8)!
            json = json.replacingOccurrences(
                of: "\"claude\": {\"working\": 0, \"quiet\": 0, \"finished\": 0}",
                with: "\"claude\": {\"working\": 1, \"waiting\": 2, \"quiet\": 0, \"finished\": 0, \"failed\": 1}"
            )
            let state = try StatusParser.parse(Data(json.utf8))
            check(state.selectedBatteryFloor == 25 && state.selectedRequireAC,
                  "next-session power policy did not decode")
            check(state.canExtend == true && state.lastSession?.restoration == .failed,
                  "extension or last-session status did not decode")
            check(state.attentionCount == 3 && state.agents.claude.detail.contains("waiting"),
                  "waiting and failed agent counts were not exposed")
        } catch { check(false, "feature status failed: \(error)") }

        var canAdd = State(phase: .ownedOn, startedAt: 1_000, deadline: 1_000 + 19_800,
                           remainingSeconds: 60, canExtend: true)
        check(canAdd.canAddThirtyMinutes, "a session at 5h30m should allow a 30-minute extension")
        canAdd.deadline = 1_000 + 20_700
        check(!canAdd.canAddThirtyMinutes, "a session at 5h45m must not offer a rejected 30-minute extension")
        canAdd.deadline = 1_000 + 19_800
        canAdd.remainingSeconds = 0
        check(!canAdd.canAddThirtyMinutes, "an expired session must not offer an extension")

        do {
            let history = try FeaturePayloadParser.history(Data("{\"schema_version\":1,\"sessions\":[\(record)]}".utf8))
            check(history.sessions.count == 1 && history.sessions[0].batteryEnd == 20,
                  "session history did not decode")
            check(SessionText.report(history.sessions[0]).contains("Last restoration attempt") &&
                  SessionText.report(history.sessions[0]).contains("Power at last attempt"),
                  "failed restoration was incorrectly described as a completed end")
        } catch { check(false, "history payload failed: \(error)") }

        do {
            let verification = try LidwiseFeatureParser.verification(Data("""
            {"schema_version":1,"expectation":"awake","result":"inconclusive","summary":"Lid evidence was too short.",
             "duration_seconds":60,"closed_lid_seconds":8.5,"sleep_seconds":0,"max_sample_gap":1.1,
             "model":"MacBookPro","os_version":"macOS 15"}
            """.utf8))
            check(verification.result == .inconclusive && verification.report.contains("8.5 seconds"),
                  "verification result did not decode into a copyable report")
        } catch { check(false, "verification payload failed: \(error)") }

        do {
            let hooks = try LidwiseFeatureParser.hookStatus(Data("""
            {"schema_version":1,
             "claude":{"supported":true,"configured":false,"events":["working","waiting","finished","failed"]},
             "codex":{"supported":true,"configured":true,"events":["finished"],"reason":"Completion only"}}
            """.utf8))
            check(hooks.codex.supported && hooks.codex.events == ["finished"],
                  "UI must render provider capability returned by the helper")
        } catch { check(false, "hook status failed: \(error)") }
    }

    static func testVerificationWorker() {
        final class FixtureRunner: CommandRunning {
            let lock = NSLock()
            var arguments: [String] = []
            var timeout: TimeInterval = 0
            func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
                lock.lock(); self.arguments = arguments; self.timeout = timeout; lock.unlock()
                return CommandResult(stdout: Data("""
                {"schema_version":1,"expectation":"sleep","result":"passed","summary":"Sleep observed.",
                 "duration_seconds":15,"closed_lid_seconds":15,"sleep_seconds":12,"max_sample_gap":1,
                 "model":"Fixture","os_version":"Fixture"}
                """.utf8), stderr: Data(), exitCode: 0, timedOut: false, launchError: nil)
            }
        }
        let runner = FixtureRunner()
        let completed = DispatchSemaphore(value: 0)
        var delivered: VerificationPayload?
        VerificationWorker(runner: runner).run(executable: "fixture", expectation: .sleep, seconds: 2) { result in
            if case .success(let payload) = result { delivered = payload }
            completed.signal()
        }
        check(completed.wait(timeout: .now() + 2) == .success, "verification worker did not complete")
        runner.lock.lock()
        let arguments = runner.arguments
        let timeout = runner.timeout
        runner.lock.unlock()
        check(arguments == ["verify", "--expect", "sleep", "--seconds", "15", "--json"],
              "verification worker did not use the bounded native command")
        check(timeout == 35 && delivered?.result == .passed,
              "verification timeout or result delivery was wrong")

        final class FailedJSONRunner: CommandRunning {
            func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
                CommandResult(stdout: Data("""
                {"schema_version":1,"expectation":"awake","result":"passed","summary":"Untrusted partial output.",
                 "duration_seconds":60,"closed_lid_seconds":60,"sleep_seconds":0,"max_sample_gap":1,
                 "model":"Fixture","os_version":"Fixture"}
                """.utf8), stderr: Data("probe timed out".utf8), exitCode: nil, timedOut: true, launchError: nil)
            }
        }
        let failed = DispatchSemaphore(value: 0)
        var rejectedFailedProcess = false
        VerificationWorker(runner: FailedJSONRunner()).run(
            executable: "fixture", expectation: .awake, seconds: 60
        ) { result in
            if case .failure = result { rejectedFailedProcess = true }
            failed.signal()
        }
        check(failed.wait(timeout: .now() + 2) == .success && rejectedFailedProcess,
              "valid-looking JSON from a timed-out probe was accepted")
    }

    static func testProcessResults() {
        let runner = ProcessRunner()
        let missing = runner.run(executable: "/tmp/lidwise-ui/no-such-helper", arguments: [], timeout: 1)
        check(!missing.succeeded && missing.launchError != nil, "missing executable must report a launch error")

        let failed = runner.run(executable: "/bin/sh", arguments: ["-c", "printf 'permission denied' >&2; exit 7"], timeout: 2)
        check(failed.exitCode == 7, "nonzero exit status was lost")
        check(failed.stderrText == "permission denied", "stderr was lost")

        let timeout = runner.run(executable: "/bin/sh", arguments: ["-c", "sleep 2"], timeout: 0.1)
        check(timeout.timedOut, "timeout was not reported")

        let pipeStart = ProcessInfo.processInfo.systemUptime
        let inheritedPipe = runner.run(executable: "/bin/sh", arguments: ["-c", "sleep 60 & exit 0"], timeout: 0.1)
        check(inheritedPipe.timedOut, "inherited pipes must share the command deadline")
        check(ProcessInfo.processInfo.systemUptime - pipeStart < 1.5,
              "an exited parent left pipe drainage blocked on its descendant")
        let stubbornStart = ProcessInfo.processInfo.systemUptime
        let stubborn = runner.run(executable: "/bin/sh", arguments: ["-c", "trap '' TERM; sleep 60 & wait"], timeout: 0.1)
        check(stubborn.timedOut && ProcessInfo.processInfo.systemUptime - stubbornStart < 1.5,
              "a child ignoring TERM escaped the deadline")

        let noisy = runner.run(executable: "/bin/sh", arguments: ["-c",
            "i=0; while [ $i -lt 6000 ]; do printf 'output-line\\n'; printf 'error-line\\n' >&2; i=$((i+1)); done"], timeout: 5)
        check(noisy.succeeded, "simultaneous output streams deadlocked")
        check(noisy.stdout.count > 50_000 && noisy.stderr.count > 50_000, "output streams were not fully drained")
    }

    static func testPendingAndStaleResults() {
        var busy = State(phase: .off)
        busy.pending = .turningOn
        check(busy.pending == .turningOn && !busy.ownsSession,
              "pending activation must not be presented as an owned session")

        let gate = RevisionGate()
        let old = gate.issue()
        let latest = gate.issue()
        check(!gate.accepts(old), "an older refresh could overwrite newer state")
        check(gate.accepts(latest), "latest refresh was rejected")
    }

    static func testMutationReconciliation() {
        let failed = CommandResult(stdout: Data(), stderr: Data("activation failed".utf8), exitCode: 1, timedOut: false, launchError: nil)
        let observedOn = CommandResult(stdout: statusJSON(phase: "owned-on"), stderr: Data(), exitCode: 0, timedOut: false, launchError: nil)
        let actual = StateReconciler.afterCommand(failed, verification: observedOn) { $0.phase == .off }
        check(actual.phase == .ownedOn && actual.commandError != nil,
              "failed activation must show the observed hold, never the previous off state")
        let unreadable = CommandResult(stdout: Data(), stderr: Data(), exitCode: nil, timedOut: true, launchError: nil)
        let unknown = StateReconciler.afterCommand(failed, verification: unreadable) { _ in true }
        check(unknown.phase == .unknown && unknown.commandError != nil,
              "failed verification must show unknown")
        let success = CommandResult(stdout: Data(), stderr: Data(), exitCode: 0, timedOut: false, launchError: nil)
        let mismatch = StateReconciler.afterCommand(success, verification: observedOn) { $0.phase == .off }
        check(mismatch.phase == .ownedOn && mismatch.commandError != nil,
              "verification mismatch must retain the observed phase")
        let nextDuration = try! StatusParser.parse(statusJSON(phase: "owned-on", extra: ", \"default_duration_seconds\": 3600"))
        check(nextDuration.durationSeconds == 21_600 && nextDuration.selectedDuration == 3_600,
              "next-session duration must not change the active session policy")
    }

    static func testActivityRefreshWorker() {
        final class BlockingRunner: CommandRunning {
            let started = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            private let lock = NSLock()
            private var calls: [[String]] = []
            var arguments: [[String]] { lock.lock(); defer { lock.unlock() }; return calls }
            func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
                lock.lock(); calls.append(arguments); lock.unlock()
                started.signal()
                _ = release.wait(timeout: .now() + 3)
                return CommandResult(stdout: Data(), stderr: Data(), exitCode: 0, timedOut: false, launchError: nil)
            }
        }
        let runner = BlockingRunner()
        let worker = ActivityRefreshWorker(runner: runner)
        let completed = DispatchSemaphore(value: 0)
        let gate = RevisionGate()
        let observationRevision = gate.issue()
        let deliveryQueue = DispatchQueue(label: "test.activity.delivery")
        var deliveredRefresh = false
        var deliveredLatestCompletion = false
        worker.refreshIfNeeded(ownedSession: true, executable: "fixture") { completed.signal() }
        check(runner.arguments.isEmpty, "owned sessions already have an observer")
        let start = Date()
        worker.refreshIfNeeded(ownedSession: false, executable: "fixture") {
            deliveryQueue.async {
                if gate.accepts(observationRevision) { deliveredRefresh = true }
                completed.signal()
            }
        }
        check(Date().timeIntervalSince(start) < 0.5, "off-state observation must return without waiting for the scanner")
        check(runner.started.wait(timeout: .now() + 2) == .success, "off-state observation must run")
        let latestRevision = deliveryQueue.sync { gate.issue() }
        worker.refreshIfNeeded(ownedSession: false, executable: "fixture") {
            deliveryQueue.async {
                deliveredLatestCompletion = true
                if gate.accepts(latestRevision) { deliveredRefresh = true }
                completed.signal()
            }
        }
        check(runner.arguments.count == 1, "overlapping activity refreshes must coalesce")
        runner.release.signal()
        check(completed.wait(timeout: .now() + 2) == .success, "activity completion must request a fresh status")
        check(deliveryQueue.sync { deliveredLatestCompletion && deliveredRefresh }, "coalesced scan must deliver the newest refresh callback")
        deliveryQueue.sync { deliveredRefresh = false }
        let beforeMutation = deliveryQueue.sync { gate.issue() }
        worker.refreshIfNeeded(ownedSession: false, executable: "fixture") {
            deliveryQueue.async {
                if gate.accepts(beforeMutation) { deliveredRefresh = true }
                completed.signal()
            }
        }
        check(runner.started.wait(timeout: .now() + 2) == .success, "later refreshes must remain available")
        deliveryQueue.sync { _ = gate.issue() } // Mutation finishes before the scan.
        runner.release.signal()
        check(completed.wait(timeout: .now() + 2) == .success, "second refresh must finish")
        check(!deliveryQueue.sync { deliveredRefresh }, "late observation must not refresh over a reconciled mutation error")
        check(runner.arguments.allSatisfy { $0 == ["__observation_once"] }, "activity worker must never send power mutations")
    }

    static func main() {
        testStatusParsing()
        testFeaturePayloads()
        testProcessResults()
        testPendingAndStaleResults()
        testMutationReconciliation()
        testActivityRefreshWorker()
        testVerificationWorker()
        if failures > 0 { exit(1) }
        print("LidwiseUIModelTests: PASS")
    }
}
