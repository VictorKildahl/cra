import Foundation

/// The main thread's call tree from `/usr/bin/sample`, cut to what a hang report needs: frames
/// that took at least `minShare` of the thread's samples, each as `<count> <function> [<image>]`
/// indented by depth. No addresses, offsets or paths (the binary list at the end names the
/// home folder), so the result can go in a public issue.
public enum PerfSampleStack {
    public static func mainThread(from text: String, minShare: Double = 0.05, limit: Int = 40) -> [String] {
        var lines: [String] = []
        var inMain = false
        var total = 0
        var baseColumn = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if !inMain {
                guard line.contains("com.apple.main-thread"), let n = leadingCount(line) else { continue }
                inMain = true
                total = n.count
                continue
            }
            // The tree's lines start with "    +"; the next thread (or the end) doesn't.
            guard line.hasPrefix("    +"), let frame = leadingCount(line) else { break }
            if lines.isEmpty { baseColumn = frame.column }
            guard total > 0, Double(frame.count) >= Double(total) * minShare else { continue }
            let depth = max(0, (frame.column - baseColumn) / 2)
            lines.append(String(repeating: " ", count: min(depth, 30)) + "\(frame.count) \(symbol(frame.rest))")
            if lines.count >= limit { break }
        }
        return lines
    }

    /// The first number on the line, the column it starts at, and the text after it.
    private static func leadingCount(_ line: String) -> (count: Int, column: Int, rest: Substring)? {
        guard let start = line.firstIndex(where: \.isNumber) else { return nil }
        let end = line[start...].firstIndex(where: { !$0.isNumber }) ?? line.endIndex
        guard let n = Int(line[start..<end]) else { return nil }
        return (n, line.distance(from: line.startIndex, to: start), line[end...])
    }

    /// `busyLoop()  (in Cra) + 156  [0x104b6903c]` → `busyLoop() [Cra]`.
    private static func symbol(_ rest: Substring) -> String {
        let s = rest.trimmingCharacters(in: .whitespaces)
        guard let open = s.range(of: "  (in ") else { return String(s.prefix(160)) }
        let name = s[..<open.lowerBound]
        let image = s[open.upperBound...].prefix { $0 != ")" }
        return String("\(name) [\(image)]".prefix(160))
    }
}
