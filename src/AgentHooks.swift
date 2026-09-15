import Darwin
import Foundation

private let hookUID = getuid()
private func hookFail(_ message: String, _ code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}
private func hookInt(_ s: String, max: Int64 = 4_102_444_800) -> Int64? {
  guard !s.isEmpty, s.allSatisfy(\.isNumber), let n = Int64(s), n >= 0, n <= max else { return nil }
  return n
}
private func hookSession(_ s: String) -> Bool {
  !s.isEmpty && s.utf8.count <= 160
    && s.unicodeScalars.allSatisfy {
      CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
      ).contains($0)
    }
}
private func hookStat(_ path: String) -> stat? {
  var s = stat()
  return lstat(path, &s) == 0 ? s : nil
}
private func ownedDirectory(_ path: String, privateOnly: Bool) throws {
  if hookStat(path) == nil {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    chmod(path, 0o700)
  }
  guard let s = hookStat(path), (s.st_mode & S_IFMT) == S_IFDIR, s.st_uid == hookUID,
    privateOnly ? (s.st_mode & 0o077) == 0 : (s.st_mode & 0o022) == 0
  else {
    throw POSIXError(.EPERM)
  }
}
private func locked<T>(_ dir: String, privateOnly: Bool, _ body: () throws -> T) throws -> T {
  try ownedDirectory(dir, privateOnly: privateOnly)
  let fd = open(dir + "/.lidwise.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
  guard fd >= 0 else { throw POSIXError(.EPERM) }
  defer { close(fd) }
  var s = stat()
  guard fstat(fd, &s) == 0, (s.st_mode & S_IFMT) == S_IFREG, s.st_uid == hookUID else {
    throw POSIXError(.EPERM)
  }
  fchmod(fd, 0o600)
  var acquired = false
  for _ in 0..<50 {
    if flock(fd, LOCK_EX | LOCK_NB) == 0 {
      acquired = true
      break
    }
    if errno != EWOULDBLOCK { break }
    usleep(20_000)
  }
  guard acquired else { throw POSIXError(.EWOULDBLOCK) }
  defer { flock(fd, LOCK_UN) }
  return try body()
}
private struct HookEvent {
  let provider, session, state: String
  let time: Int64
}
private func events(_ path: String, limit: Int = 1024) -> [HookEvent] {
  guard let s = hookStat(path), (s.st_mode & S_IFMT) == S_IFREG, s.st_uid == hookUID,
    (s.st_mode & 0o077) == 0, s.st_size <= 262144,
    let d = FileManager.default.contents(atPath: path), let text = String(data: d, encoding: .utf8)
  else { return [] }
  return text.split(separator: "\n").suffix(limit).compactMap { line in
    let p = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard p.count == 4, ["claude", "codex"].contains(p[0]),
      ["working", "waiting", "finished", "failed"].contains(p[2]), hookSession(p[1]),
      let t = hookInt(p[3])
    else { return nil }
    return HookEvent(provider: p[0], session: p[1], state: p[2], time: t)
  }
}
private func record(
  _ path: String, _ provider: String, _ state: String, _ session: String, _ time: Int64,
  _ now: Int64, _ maximum: Int
) throws {
  guard ["claude", "codex"].contains(provider),
    ["working", "waiting", "finished", "failed"].contains(state), hookSession(session),
    time <= now + 5
  else { throw POSIXError(.EINVAL) }
  let dir = (path as NSString).deletingLastPathComponent
  let parent = (dir as NSString).deletingLastPathComponent
  try ownedDirectory(parent, privateOnly: true)
  try locked(dir, privateOnly: true) {
    var list = events(path, limit: maximum)
    if let newest = list.filter({ $0.provider == provider && $0.session == session }).map(\.time)
      .max(), newest > time
    {
      return
    }
    list.removeAll { $0.provider == provider && $0.session == session }
    list.append(HookEvent(provider: provider, session: session, state: state, time: time))
    list = Array(list.suffix(maximum))
    let data = Data(
      (list.map { "\($0.provider)\t\($0.session)\t\($0.state)\t\($0.time)" }.joined(separator: "\n")
        + (list.isEmpty ? "" : "\n")).utf8)
    let tmp = dir + "/.events." + UUID().uuidString
    guard
      FileManager.default.createFile(
        atPath: tmp, contents: data, attributes: [.posixPermissions: 0o600])
    else { throw POSIXError(.EIO) }
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    guard rename(tmp, path) == 0 else { throw POSIXError(.EIO) }
  }
}
private func receiveHook(_ path: String, _ kind: String, _ now: Int64, _ maximum: Int) throws {
  var d = Data()
  while d.count <= 65_536 {
    let chunk =
      try FileHandle.standardInput.read(upToCount: min(16_384, 65_537 - d.count)) ?? Data()
    if chunk.isEmpty { break }
    d.append(chunk)
  }
  guard d.count <= 65_536,
    let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
    let session = o["session_id"] as? String, hookSession(session)
  else { return }
  var state: String?
  switch kind {
  case "user-prompt":
    state = o["hook_event_name"] as? String == "UserPromptSubmit" ? "working" : nil
  case "notification":
    state =
      o["hook_event_name"] as? String == "Notification"
        && [
          "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
        ].contains(o["notification_type"] as? String ?? "") ? "waiting" : nil
  case "stop-failure": state = o["hook_event_name"] as? String == "StopFailure" ? "failed" : nil
  case "stop":
    guard o["hook_event_name"] as? String == "Stop" else {
      state = nil
      break
    }
    guard o.keys.contains("background_tasks"), o.keys.contains("session_crons"),
      o["background_tasks"] is [Any], o["session_crons"] is [Any]
    else {
      state = nil
      break
    }
    let bg = (o["background_tasks"] as? [Any])?.count ?? 0
    let crons = (o["session_crons"] as? [Any])?.count ?? 0
    state = bg + crons == 0 ? "finished" : nil
  default: throw POSIXError(.EINVAL)
  }
  if let state { try record(path, "claude", state, session, now, now, maximum) }
}
private func json(_ o: Any) -> Data {
  (try? JSONSerialization.data(
    withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
}
private func own(_ value: Any, _ prefix: String) -> Bool {
  guard let h = value as? [String: Any], let c = h["command"] as? String else { return false }
  return c.hasPrefix(prefix + " ")
}
private func ownedHookCount(_ input: [String: Any], _ prefix: String) -> Int {
  guard let hooks = input["hooks"] as? [String: Any] else { return 0 }
  return managedEvents.reduce(0) { count, event in
    let groups = hooks[event] as? [[String: Any]] ?? []
    return count
      + groups.reduce(0) { $0 + (($1["hooks"] as? [Any])?.filter { own($0, prefix) }.count ?? 0) }
  }
}
private let managedEvents = ["UserPromptSubmit", "Notification", "Stop", "StopFailure"]
private func validateHookShape(_ input: [String: Any]) throws {
  guard let rawHooks = input["hooks"] else { return }
  guard let hooks = rawHooks as? [String: Any] else {
    throw NSError(
      domain: "Lidwise", code: 6,
      userInfo: [NSLocalizedDescriptionKey: "hooks must be a JSON object"])
  }
  for event in managedEvents where hooks[event] != nil {
    guard hooks[event] is [[String: Any]] else {
      throw NSError(
        domain: "Lidwise", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "\(event) hooks must be an array"])
    }
  }
}
private func transformed(_ input: [String: Any], _ prefix: String, _ install: Bool) -> [String: Any]
{
  var root = input
  var hooks = root["hooks"] as? [String: Any] ?? [:]
  for (event, raw) in hooks {
    guard let groups = raw as? [[String: Any]] else { continue }
    hooks[event] = groups.compactMap { group in
      guard let hs = group["hooks"] as? [Any] else { return group }
      var g = group
      let kept = hs.filter { !own($0, prefix) }
      if kept.isEmpty { return nil }
      g["hooks"] = kept
      return g
    }
  }
  if install {
    for (event, kind, matcher) in [
      ("UserPromptSubmit", "user-prompt", nil),
      (
        "Notification", "notification",
        "permission_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input"
      ), ("Stop", "stop", nil), ("StopFailure", "stop-failure", nil),
    ] as [(String, String, String?)] {
      var groups = hooks[event] as? [[String: Any]] ?? []
      var group: [String: Any] = [
        "hooks": [["type": "command", "command": prefix + " " + kind, "timeout": 5]]
      ]
      if let matcher { group["matcher"] = matcher }
      groups.append(group)
      hooks[event] = groups
    }
  }
  if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
  return root
}
private func settings(_ action: String, _ path: String, _ prefix: String) throws {
  let fm = FileManager.default
  let existed = fm.fileExists(atPath: path)
  if !existed {
    if action == "status" {
      print("{\"configured\":false}")
      return
    }
    if action == "preview" {
      let old: [String: Any] = [:]
      print(
        String(
          data: json(["old": old, "new": transformed(old, prefix, true), "changed": true]),
          encoding: .utf8)!)
      return
    }
    if action == "remove" { return }
    try ownedDirectory((path as NSString).deletingLastPathComponent, privateOnly: false)
  }
  let oldData: Data
  let old: [String: Any]
  let settingsMode: mode_t
  if existed {
    guard let s = hookStat(path), (s.st_mode & S_IFMT) == S_IFREG, s.st_uid == hookUID,
      s.st_size <= 1_048_576
    else { throw POSIXError(.EPERM) }
    oldData = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let parsed = try JSONSerialization.jsonObject(with: oldData) as? [String: Any] else {
      throw POSIXError(.EINVAL)
    }
    old = parsed
    settingsMode = s.st_mode & 0o777
  } else {
    oldData = Data("{}\n".utf8)
    old = [:]
    settingsMode = 0o600
  }
  try validateHookShape(old)
  let configured = ownedHookCount(old, prefix) == managedEvents.count
  if action == "status" {
    print("{\"configured\":\(configured)}")
    return
  }
  let next = transformed(old, prefix, action != "remove")
  if action == "preview" {
    print(
      String(
        data: json(["old": old, "new": next, "changed": !(old as NSDictionary).isEqual(to: next)]),
        encoding: .utf8)!)
    return
  }
  guard !(old as NSDictionary).isEqual(to: next) else { return }
  let dir = (path as NSString).deletingLastPathComponent
  try locked(dir, privateOnly: false) {
    // Re-read under lock to avoid overwriting a concurrent editor.
    if existed {
      guard
        let current = try JSONSerialization.jsonObject(
          with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any],
        (current as NSDictionary).isEqual(to: old)
      else {
        throw NSError(
          domain: "Lidwise", code: 5,
          userInfo: [NSLocalizedDescriptionKey: "settings changed concurrently; retry"])
      }
    } else if fm.fileExists(atPath: path) {
      throw NSError(
        domain: "Lidwise", code: 5,
        userInfo: [NSLocalizedDescriptionKey: "settings appeared concurrently; retry"])
    }
    if existed {
      let backup =
        path + ".lidwise-backup." + String(Int(Date().timeIntervalSince1970)) + "."
        + UUID().uuidString
      try oldData.write(to: URL(fileURLWithPath: backup), options: .atomic)
      chmod(backup, 0o600)
    }
    let tmp = dir + "/.settings." + UUID().uuidString
    try (json(next) + Data("\n".utf8)).write(to: URL(fileURLWithPath: tmp), options: .atomic)
    chmod(tmp, settingsMode)
    guard rename(tmp, path) == 0 else {
      try? fm.removeItem(atPath: tmp)
      throw POSIXError(.EIO)
    }
  }
}

func runHookCommand(_ a: [String]) -> Bool {
  guard a.count > 1 else { return false }
  do {
    switch a[1] {
    case "--event-record" where a.count == 9:
      guard let t = hookInt(a[6]), let now = hookInt(a[7]), let max = Int(a[8]),
        (1...1024).contains(max)
      else { exit(2) }
      try record(a[2], a[3], a[4], a[5], t, now, max)
      return true
    case "--event-hook" where a.count == 7:
      guard let now = hookInt(a[4]), let max = Int(a[5]), a[3] == "claude" else { exit(2) }
      // Observation callbacks must never affect Claude Code's control flow.
      try? receiveHook(a[2], a[6], now, max)
      return true
    case "--events-read" where a.count == 5:
      guard let now = hookInt(a[3]), let age = hookInt(a[4]) else { exit(2) }
      for e in events(a[2]) where e.time <= now && now - e.time <= age {
        print("\(e.provider)\t\(e.session)\t\(e.state)\t\(e.time)")
      }
      return true
    case "--claude-settings" where a.count == 5:
      try settings(a[2], a[3], a[4])
      return true
    default: return false
    }
  } catch { hookFail(error.localizedDescription) }
}
