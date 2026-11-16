// waitwin <t0-epoch-ms> <timeout-s> <rootpid>: polls every 2 ms until a layer-0 window >200x200 of rootpid's tree is on
// screen; prints ms since t0 (epoch ms) and the window id. Exit 1 on timeout. With "new" as 4th arg, ignores windows on
// screen when it starts.
import CoreGraphics; import Foundation
let a = CommandLine.arguments
let t0 = Double(a[1])!, timeout = Double(a[2])!, root = Int32(a[3])!
// 4th arg "ignore:<id,id,…>": windows on screen before the action (taken before it, so a fast window isn't missed).
let ignore = a.count > 4 ? Set(a[4].dropFirst(7).split(separator: ",").compactMap { Int($0) }) : Set<Int>()
let onlyNew = a.count > 4
func tree() -> Set<Int32> {
  var all: Set<Int32> = [root]; var frontier = [root]
  let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-axo", "pid=,ppid="]
  let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
  let rows = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: "\n").map { $0.split(separator: " ").compactMap { Int32($0) } }
  while let x = frontier.popLast() { for r in rows where r.count == 2 && r[1] == x && !all.contains(r[0]) { all.insert(r[0]); frontier.append(r[0]) } }
  return all
}
func wins(_ pids: Set<Int32>) -> [Int] {
  let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
  return list.compactMap { w in
    guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid), (w[kCGWindowLayer as String] as? Int) == 0,
          let b = w[kCGWindowBounds as String] as? [String: Double], (b["Width"] ?? 0) > 300, (b["Height"] ?? 0) > 300,
          ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.5 else { return nil }
    return w[kCGWindowNumber as String] as? Int }
}
var pids = tree(); let before = onlyNew ? ignore : []
let start = Date()
var n = 0
while Date().timeIntervalSince(start) < timeout {
  if n % 50 == 0 { pids = tree() }; n += 1
  if let w = wins(pids).first(where: { !before.contains($0) }) {
    print(String(format: "%.1f %d", Date().timeIntervalSince1970 * 1000 - t0, w)); exit(0)
  }
  usleep(2000)
}
exit(1)
