import Foundation
import Darwin

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

protocol CommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
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
