import Foundation

/// A plain-language reading of a report for the Performance pane's Overview.
public struct PerfInsight: Codable, Equatable, Sendable, Identifiable {
    public enum Severity: String, Codable, Sendable { case info, warning }

    public var id: String
    public var severity: Severity
    public var title: String
    public var detail: String

    public init(id: String, severity: Severity, title: String, detail: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

/// The rules behind the insights. Each one reads the report alone, so the pane, perf.json and
/// a test all agree.
public enum PerfInsights {
    public static let lowDiskBytes: Int64 = 5 << 30
    public static let largeFootprintBytes: Int64 = 8 << 30
    /// Short stalls per hour of the session that are worth a line.
    public static let frequentStallsPerHour = 30.0

    public static func evaluate(_ r: PerfReport) -> [PerfInsight] {
        var out: [PerfInsight] = []
        if let p = r.session.previous, p.abnormal {
            out.append(PerfInsight(id: "previous-abnormal", severity: .warning, title: "The last session ended without quitting",
                                   detail: "Cra \(p.craVersion) crashed, was forced to quit or the Mac lost power. Its last minute is in the export."))
        }
        let m = r.mainThread
        if m.longStalls > 0 {
            out.append(PerfInsight(id: "freezes", severity: .warning,
                                   title: "Cra froze \(m.longStalls) time\(m.longStalls == 1 ? "" : "s") for a second or more",
                                   detail: "The longest lasted \(Self.duration(m.longestMs))\(m.hangs > 0 ? "; \(m.hangs) went past 2 s" : "")."))
        }
        let hours = max(r.session.uptimeSeconds / 3600, 1.0 / 12)
        if m.stalls >= 5, Double(m.stalls) / hours >= frequentStallsPerHour {
            out.append(PerfInsight(id: "stalls", severity: .info, title: "Frequent short stalls",
                                   detail: "\(m.stalls) pauses of a quarter second or more since launch."))
        }
        let crashes = r.counters[PerfCounter.rendererTerminated.rawValue]?.values.reduce(0, +) ?? 0
        if crashes > 0 {
            out.append(PerfInsight(id: "renderer-crashes", severity: .warning,
                                   title: "\(crashes) page\(crashes == 1 ? "" : "s") stopped (“Aw, Snap!”)",
                                   detail: "A page's process crashed, ran out of memory or was ended."))
        }
        let unresponsive = r.counters[PerfCounter.rendererUnresponsive.rawValue]?.values.reduce(0, +) ?? 0
        if unresponsive > 0 {
            out.append(PerfInsight(id: "unresponsive", severity: .warning, title: "\(unresponsive) page\(unresponsive == 1 ? "" : "s") stopped responding",
                                   detail: "Chromium asked whether to wait or close the page."))
        }
        if let s = r.system {
            if s.memoryPressure == .warning || s.memoryPressure == .critical {
                out.append(PerfInsight(id: "memory-pressure", severity: .warning, title: "The Mac is short of memory",
                                       detail: "macOS reports \(s.memoryPressure.rawValue) memory pressure; pages may reload and everything slows down."))
            }
            if s.thermalState == "serious" || s.thermalState == "critical" {
                out.append(PerfInsight(id: "thermal", severity: .info, title: "The Mac is running hot",
                                       detail: "macOS slows the processor down until it cools."))
            }
            if s.lowPowerMode {
                out.append(PerfInsight(id: "low-power", severity: .info, title: "Low Power Mode is on", detail: "Video and scrolling may be less smooth."))
            }
        }
        if let free = r.storage.freeDiskBytes ?? r.system?.freeDiskBytes, free < lowDiskBytes {
            out.append(PerfInsight(id: "low-disk", severity: .warning, title: "The disk is almost full",
                                   detail: "\(bytes(free)) free. Chromium's caches and swap need room."))
        }
        let footprint = r.processes.reduce(Int64(0)) { $0 + $1.footprintBytes }
        if footprint >= largeFootprintBytes {
            let slept = r.tabs.latest?.slept ?? 0
            out.append(PerfInsight(id: "footprint", severity: .info, title: "Cra uses \(bytes(footprint)) of memory",
                                   detail: slept > 0 ? "Tab sleeping has \(slept) tab\(slept == 1 ? "" : "s") asleep." : "Tab sleeping (Settings ▸ Tabs) closes pages you haven't looked at in a while."))
        }
        return out
    }

    public static func duration(_ ms: Double) -> String {
        ms >= 1000 ? String(format: "%.1f s", ms / 1000) : "\(Int(ms.rounded())) ms"
    }

    public static func bytes(_ n: Int64) -> String {
        let gb = Double(n) / Double(1 << 30)
        return gb >= 1 ? String(format: "%.1f GB", gb) : "\(n >> 20) MB"
    }
}

/// Settings ▸ Performance ▸ Copy Summary: a few lines to paste into an issue. Never a site name,
/// whatever "Hide site names" says: a summary gets pasted where nobody reviews the zip.
public enum PerfSummary {
    public static func text(_ r: PerfReport) -> String {
        let m = r.mainThread
        var lines = [
            "Cra \(r.session.craVersion), Chromium \(r.session.chromiumVersion), launch \(r.session.launch), up \(Int(r.session.uptimeSeconds / 60)) min",
            "Main thread: \(m.stalls) stalls ≥250 ms, \(m.longStalls) ≥1 s, \(m.hangs) ≥2 s, longest \(PerfInsights.duration(m.longestMs)) (p99 pass \(PerfInsights.duration(m.passes.percentile(0.99))))",
        ]
        if let p = r.session.previous { lines.append("Previous session: \(p.abnormal ? "ended without quitting" : "quit normally") (Cra \(p.craVersion))") }
        for g in r.processes where g.count > 0 {
            lines.append("\(g.kind.rawValue) ×\(g.count): \(String(format: "%.1f", g.cpuPct)) % CPU, \(PerfInsights.bytes(g.footprintBytes))")
        }
        if let s = r.system {
            lines.append("Mac: \(s.cpuPct.map { String(format: "%.0f", $0) + " % CPU" } ?? "CPU n/a"), memory \(s.memoryPressure.rawValue), thermal \(s.thermalState)\(s.lowPowerMode ? ", Low Power Mode" : "")")
        }
        if let t = r.tabs.latest {
            lines.append("Tabs: \(t.tabs), \(t.live) loaded, \(t.slept) asleep, \(t.windows) window\(t.windows == 1 ? "" : "s")")
        }
        for (key, metric) in [("tab switch", PerfMetric.tabSwitch), ("page create", .pageCreate), ("page load", .pageLoad)] {
            if let h = r.timings[metric.rawValue], h.count > 0 {
                lines.append("\(key): median \(PerfInsights.duration(h.percentile(0.5))), p95 \(PerfInsights.duration(h.percentile(0.95))) (\(h.count))")
            }
        }
        if r.tabs.longTasks > 0 { lines.append("Page long tasks: \(r.tabs.longTasks), \(PerfInsights.duration(r.tabs.longTaskMs)) in all") }
        for (counter, keys) in r.counters.sorted(by: { $0.key < $1.key }) where !keys.isEmpty {
            lines.append("\(counter): " + keys.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        for i in r.insights { lines.append("• \(i.title)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
