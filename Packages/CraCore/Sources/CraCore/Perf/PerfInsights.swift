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
    /// What recording may cost, in percent of one core (docs/performance.md).
    public static let selfCostBudgetPct = 0.1
    /// Cra's average CPU, percent of one core, while nobody used the Mac, over at least
    /// `idleMinSamples` 5-second samples, that is worth a line.
    public static let idleCpuPct = 10.0
    public static let idleMinSamples = 12

    public static func evaluate(_ r: PerfReport) -> [PerfInsight] {
        var out: [PerfInsight] = []
        if let p = r.session.previous, p.abnormal {
            out.append(PerfInsight(id: "previous-abnormal", severity: .warning, title: "The last session ended without quitting",
                                   detail: "Cra \(p.craVersion) crashed, was forced to quit or the Mac lost power. Its last minute is in the export."))
        }
        let m = r.mainThread
        if m.longFreezes > 0 {
            out.append(PerfInsight(id: "freezes", severity: .warning,
                                   title: "Cra froze \(m.longFreezes) time\(m.longFreezes == 1 ? "" : "s") for a second or more",
                                   detail: "The longest lasted \(Self.duration(m.longestFreezeMs))\(m.hangs > 0 ? "; \(m.hangs) went past 2 s" : "")."))
        }
        let hours = max(r.session.awakeSeconds / 3600, 1.0 / 12)
        if m.freezes >= 5, Double(m.freezes) / hours >= frequentStallsPerHour {
            out.append(PerfInsight(id: "stalls", severity: .info, title: "Frequent short stalls",
                                   detail: "\(m.freezes) pauses of a quarter second or more since launch."))
        }
        if m.outsideFreezes > 0 {
            let longest = m.longestPassMs > m.longestFreezeMs ? " The longest lasted \(Self.duration(m.longestPassMs))\(m.longestPassMode.map { " (\($0))" } ?? "")." : ""
            out.append(PerfInsight(id: "outside-freezes", severity: .info,
                                   title: "\(m.outsideFreezes) long pass\(m.outsideFreezes == 1 ? "" : "es") in menus, drags, alerts or start-up",
                                   detail: "Not counted as freezes: Cra was in a loop of its own on purpose.\(longest)"))
        }
        if r.selfCost.cpuPct > selfCostBudgetPct {
            out.append(PerfInsight(id: "profiler-overhead", severity: .info,
                                   title: "Recording costs \(String(format: "%.3f", r.selfCost.cpuPct)) % of a core",
                                   detail: "Over its \(selfCostBudgetPct) % budget. The numbers still hold; selfCost in perf.json says which part costs it."))
        }
        if r.idle.samples >= idleMinSamples, r.idle.cpuPct >= idleCpuPct {
            out.append(PerfInsight(id: "idle-cpu", severity: .info,
                                   title: "Cra kept working while the Mac was idle",
                                   detail: "\(Int(r.idle.cpuPct.rounded())) % of a core on average over \(r.idle.samples * 5 / 60) min without keyboard or mouse input. A playing video counts too."))
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
            "Main thread: \(m.freezes) freezes ≥250 ms (\(m.longFreezes) ≥1 s, \(m.hangs) ≥2 s), longest freeze \(PerfInsights.duration(m.longestFreezeMs)); "
                + "longest pass \(PerfInsights.duration(m.longestPassMs))\(m.longestPassMode.map { " (\($0))" } ?? ""), "
                + "\(m.outsideFreezes) outside freezes (menus, drags, alerts, start-up); p99 pass \(PerfInsights.duration(m.passes.percentile(0.99)))",
        ]
        if let s = m.slowPass {
            lines.append("Slow pass sampled: \(PerfInsights.duration(s.endedMs ?? s.stalledMs)) (\(s.mode)), top: \(s.stack.first?.trimmingCharacters(in: .whitespaces) ?? s.stackNote ?? "no stack")")
        }
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
        if r.tabs.longFrames > 0 { lines.append("Page long frames: \(r.tabs.longFrames), longest \(PerfInsights.duration(r.tabs.longestFrameMs))") }
        if r.tabs.videoFrames > 0 { lines.append("Video: \(r.tabs.droppedVideoFrames) of \(r.tabs.videoFrames) frames dropped") }
        if r.idle.samples > 0 { lines.append("Idle: \(String(format: "%.1f", r.idle.cpuPct)) % CPU over \(r.idle.samples * 5 / 60) min") }
        lines.append("Recording: \(String(format: "%.3f", r.selfCost.cpuPct)) % of a core")
        for (counter, keys) in r.counters.sorted(by: { $0.key < $1.key }) where !keys.isEmpty {
            lines.append("\(counter): " + keys.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        for i in r.insights { lines.append("• \(i.title)") }
        return lines.joined(separator: "\n") + "\n"
    }
}
