// Bounded, local JSONL event parsing. No transcript text is emitted.
import Foundation

@main
struct AgentScan {
  static func main() {
    let arguments = CommandLine.arguments
    if runHookCommand(arguments) { return }
    if arguments.count >= 4 && arguments[1] == "--run-bounded" {
      guard let timeout = TimeInterval(arguments[2]), timeout > 0, timeout <= 20,
        arguments[3].hasPrefix("/")
      else {
        exit(2)
      }
      let result = ProcessRunner().run(
        executable: arguments[3], arguments: Array(arguments.dropFirst(4)), timeout: timeout)
      FileHandle.standardOutput.write(result.stdout)
      FileHandle.standardError.write(result.stderr)
      if result.succeeded { exit(0) }
      let exitCode = result.exitCode ?? 1
      exit(exitCode == 0 ? 1 : exitCode)
    }
    let includeTime = arguments.count == 4 && arguments[1] == "--marker-with-time"
    if arguments.count != 3 && !includeTime { exit(2) }
    let provider = includeTime ? arguments[2] : arguments[1]
    let path = includeTime ? arguments[3] : arguments[2]
    let url = URL(fileURLWithPath: path)
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let length = try handle.seekToEnd()
      // Inspect metadata separately: Codex child logs need not live in a subfolder.
      try handle.seek(toOffset: 0)
      let prefix = try handle.read(upToCount: 65536) ?? Data()
      let firstLine = prefix.split(separator: 10, maxSplits: 1).first ?? Data.SubSequence()
      if let meta = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
        meta["type"] as? String == "session_meta",
        let payload = meta["payload"] as? [String: Any],
        let source = payload["source"] as? [String: Any], source["subagent"] != nil
      {
        print("child")
        exit(0)
      }
      // A pathological trace cannot make a status worker load an unbounded file.
      let limit: UInt64 = 2 * 1024 * 1024
      let offset = length > limit ? length - limit : 0
      try handle.seek(toOffset: offset)
      let data = try handle.read(upToCount: Int(limit)) ?? Data()
      var lines = data.split(separator: 10, omittingEmptySubsequences: true)
      if offset > 0 && !lines.isEmpty { lines.removeFirst() }  // partial JSON line
      var marker = ""
      var markerTimeMilliseconds: Int64 = 0
      let fractionalTimestampParser = ISO8601DateFormatter()
      fractionalTimestampParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      let wholeTimestampParser = ISO8601DateFormatter()
      for line in lines.suffix(100) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
          let type = object["type"] as? String
        else { continue }
        let payload = object["payload"] as? [String: Any]
        let event = payload?["type"] as? String
        var nextMarker = ""
        if provider == "codex" && type == "event_msg" && event == "task_complete" {
          nextMarker = "finished"
        } else if provider == "claude" && type == "result",
          let subtype = object["subtype"] as? String,
          ["success", "completed"].contains(subtype)
        {
          nextMarker = "finished"
        } else if provider == "codex" && type == "response_item"
          && ([
            "reasoning", "function_call", "custom_tool_call", "function_call_output",
            "custom_tool_call_output",
          ].contains(event ?? "")
            || (event == "message"
              && ["user", "assistant"].contains(payload?["role"] as? String ?? "")))
        {
          // Desktop writes resumed-turn activity as response items. Metadata
          // alone must not revive an earlier completed turn.
          nextMarker = "working"
        } else if ["assistant", "user", "tool"].contains(type)
          || (type == "event_msg"
            && [
              "user_message", "agent_reasoning", "agent_message", "function_call",
              "custom_tool_call",
            ].contains(event ?? ""))
        {
          nextMarker = "working"
        }
        if !nextMarker.isEmpty {
          marker = nextMarker
          if let raw = object["timestamp"] as? String,
            let date = fractionalTimestampParser.date(from: raw)
              ?? wholeTimestampParser.date(from: raw)
          {
            let seconds = date.timeIntervalSince1970
            if seconds.isFinite, seconds >= 0, seconds <= 4_102_444_805 {
              markerTimeMilliseconds = Int64((seconds * 1_000).rounded(.down))
            } else {
              markerTimeMilliseconds = 0
            }
          } else {
            markerTimeMilliseconds = 0
          }
        }
      }
      if includeTime { print("\(marker)\t\(markerTimeMilliseconds)") } else { print(marker) }
    } catch {
      // Unreadable or replaced logs are unavailable, never completed.
      exit(1)
    }
  }
}
