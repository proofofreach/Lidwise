// Bounded, local JSONL event parsing. No transcript text is emitted.
import Foundation

let arguments = CommandLine.arguments
if arguments.count != 3 { exit(2) }
let url = URL(fileURLWithPath: arguments[2])
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
       let source = payload["source"] as? [String: Any], source["subagent"] != nil {
        print("child")
        exit(0)
    }
    // A pathological trace cannot make a status worker load an unbounded file.
    let limit: UInt64 = 2 * 1024 * 1024
    let offset = length > limit ? length - limit : 0
    try handle.seek(toOffset: offset)
    let data = try handle.read(upToCount: Int(limit)) ?? Data()
    var lines = data.split(separator: 10, omittingEmptySubsequences: true)
    if offset > 0 && !lines.isEmpty { lines.removeFirst() } // partial JSON line
    var marker = ""
    for line in lines.suffix(100) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let type = object["type"] as? String else { continue }
        let payload = object["payload"] as? [String: Any]
        let event = payload?["type"] as? String
        if arguments[1] == "codex" && type == "event_msg" && event == "task_complete" {
            marker = "finished"
        } else if arguments[1] == "claude" && type == "result",
                  let subtype = object["subtype"] as? String,
                  ["success", "completed"].contains(subtype) {
            marker = "finished"
        } else if arguments[1] == "codex" && type == "response_item" &&
                    (["reasoning", "function_call", "custom_tool_call", "function_call_output", "custom_tool_call_output"].contains(event ?? "") ||
                     (event == "message" && ["user", "assistant"].contains(payload?["role"] as? String ?? ""))) {
            // Desktop writes resumed-turn activity as response items. Metadata
            // alone must not revive an earlier completed turn.
            marker = "working"
        } else if ["assistant", "user", "tool"].contains(type) ||
                    (type == "event_msg" && ["user_message", "agent_reasoning", "agent_message", "function_call", "custom_tool_call"].contains(event ?? "")) {
            marker = "working"
        }
    }
    print(marker)
} catch {
    // Unreadable or replaced logs are unavailable, never completed.
    exit(1)
}
