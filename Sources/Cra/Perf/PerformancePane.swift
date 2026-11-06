import AppKit
import SwiftUI

/// Settings ▸ Performance (GitHub #91): what the recorder measured this session, read every two
/// seconds while the pane is on screen and never while it isn't. Card style like Privacy. Not in
/// Dia or Arc: Cra's own, for reports of freezes that are gone by the time they are written up.
struct PerformancePane: View {
    let nav: SettingsNavigation
    let actions: SettingsActions
    @Environment(SidebarStore.self) private var store
    @State private var section = Section.overview
    @State private var report: PerfReport?
    @State private var copied = false

    enum Section: String, CaseIterable { case overview = "Overview", events = "Events", export = "Export" }

    var body: some View {
        @Bindable var store = store
        SettingsCardPane {
            Picker("", selection: $section) { ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            switch section {
            case .overview: overview($store.settings.perfRecording)
            case .events: events
            case .export: export($store.settings.perfHidesSiteNames)
            }
        }
        .task(id: RefreshKey(open: nav.isOpen, recording: store.settings.perfRecording)) {
            report = nil
            guard nav.isOpen, store.settings.perfRecording else { return }
            while !Task.isCancelled {
                if let r = PerfRecorder.shared { r.snapshot { report = $0 } }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private struct RefreshKey: Equatable { var open: Bool; var recording: Bool }

    // MARK: Overview

    @ViewBuilder private func overview(_ recording: Binding<Bool>) -> some View {
        SettingsCard {
            SettingsCardRow {
                HStack(spacing: 5.5) {
                    SettingsGlyph(symbol: "gauge.with.dots.needle.67percent", color: Color(nsColor: .systemBlue))
                    Text("Record performance").font(.system(size: 13))
                }
            } trailing: {
                Toggle("Record performance", isOn: recording).toggleStyle(.switch).labelsHidden()
            }
        }
        SettingsFootnote("Cra measures itself on this Mac: freezes, CPU and memory per process, tab timings. Nothing leaves the Mac unless you export it with Help ▸ Export Diagnostics.")

        if let r = report {
            if !r.insights.isEmpty {
                SettingsHeader("Findings").padding(.top, 20)
                SettingsCard {
                    ForEach(Array(r.insights.enumerated()), id: \.element.id) { i, insight in
                        if i > 0 { SettingsCardDivider() }
                        SettingsCardRow {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: insight.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                                    .foregroundStyle(insight.severity == .warning ? Color(nsColor: .systemOrange) : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(insight.title).font(.system(size: 13))
                                    Text(insight.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        } trailing: { EmptyView() }
                    }
                }
            }
            let m = r.mainThread
            card("Main thread", [
                ("Stalls of ¼ s or more", "\(m.freezes)"),
                ("Freezes of 1 s or more", "\(m.longFreezes)"),
                ("Longest freeze", m.longestFreezeMs > 0 ? PerfInsights.duration(m.longestFreezeMs) : "–"),
                ("In menus, drags, alerts, start-up", "\(m.outsideFreezes)"),
                ("Longest pass", m.longestPassMs > 0 ? PerfInsights.duration(m.longestPassMs) + (m.longestPassMode.map { " (\($0))" } ?? "") : "–"),
                ("Typical pass (99 %)", PerfInsights.duration(m.passes.percentile(0.99))),
            ])
            card("Processes", r.processes.filter { $0.count > 0 }.map { g in
                (g.kind.label + (g.count > 1 ? " ×\(g.count)" : ""),
                 g.available ? "\(String(format: "%.1f", g.cpuPct)) % CPU · \(PerfInsights.bytes(g.footprintBytes))" : "not available")
            })
            if let s = r.system {
                card("Mac", [
                    ("CPU, all cores", s.cpuPct.map { "\(Int($0.rounded())) %" } ?? "–"),
                    ("Memory pressure", s.memoryPressure.rawValue.capitalized),
                    ("Temperature", s.thermalState.capitalized),
                    ("Low Power Mode", s.lowPowerMode ? "On" : "Off"),
                    ("Free disk", s.freeDiskBytes.map(PerfInsights.bytes) ?? "–"),
                ])
            }
            card("Tabs", tabRows(r))
            Text("Session \(r.session.id), launch \(r.session.launch), up \(Int(r.session.uptimeSeconds / 60)) min · recording costs \(String(format: "%.3f", r.selfCost.cpuPct)) % of a core")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.leading, 8).padding(.top, 12)
        } else if !recording.wrappedValue {
            SettingsFootnote("Recording is off: no samples, no timers, nothing written. Files already recorded stay until you clear them.")
                .padding(.top, 12)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 24)
        }
    }

    private func tabRows(_ r: PerfReport) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let t = r.tabs.latest { rows.append(("Tabs", "\(t.tabs) · \(t.live) loaded · \(t.slept) asleep")) }
        for (title, metric) in [("Tab switch", PerfMetric.tabSwitch), ("New page", .pageCreate), ("Page load", .pageLoad), ("Waking a slept tab", .tabWake)] {
            guard let h = r.timings[metric.rawValue], h.count > 0 else { continue }
            rows.append((title, "\(PerfInsights.duration(h.percentile(0.5))) typical · \(PerfInsights.duration(h.percentile(0.95))) slow"))
        }
        if r.tabs.longTasks > 0 { rows.append(("Busy page (long tasks)", "\(r.tabs.longTasks) · \(PerfInsights.duration(r.tabs.longTaskMs))")) }
        if r.tabs.longFrames > 0 { rows.append(("Late frames", "\(r.tabs.longFrames) · longest \(PerfInsights.duration(r.tabs.longestFrameMs))")) }
        if r.tabs.videoFrames > 0 { rows.append(("Video frames dropped", "\(r.tabs.droppedVideoFrames) of \(r.tabs.videoFrames)")) }
        return rows
    }

    @ViewBuilder private func card(_ title: String, _ rows: [(String, String)]) -> some View {
        if !rows.isEmpty {
            SettingsHeader(title).padding(.top, 20)
            SettingsCard {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { SettingsCardDivider() }
                    SettingsCardRow {
                        Text(row.0).font(.system(size: 13))
                    } trailing: {
                        Text(row.1).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Events

    @ViewBuilder private var events: some View {
        let list = report.map(Self.timeline) ?? []
        if list.isEmpty {
            SettingsFootnote(report == nil ? "Recording is off." : "Nothing has happened this session: no stalls, crashed pages or failed loads.")
        } else {
            SettingsCard {
                ForEach(Array(list.prefix(100).enumerated()), id: \.offset) { i, e in
                    if i > 0 { SettingsCardDivider() }
                    SettingsCardRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).font(.system(size: 13))
                            if !e.detail.isEmpty {
                                Text(e.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    } trailing: {
                        Text(e.time).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private struct Row { var at: Double; var time: String; var title: String; var detail: String }

    /// Stalls and events, newest first.
    private static func timeline(_ r: PerfReport) -> [Row] {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        func time(_ at: Double) -> String { f.string(from: r.session.startedAt.addingTimeInterval(at)) }
        var rows = r.mainThread.recent.map { s in
            Row(at: s.at, time: time(s.at),
                title: "\(s.freeze ? (s.kind == .stall ? "Stall" : "Freeze") : "Busy \(s.mode) loop") \(PerfInsights.duration(s.ms))",
                detail: ([s.site].compactMap { $0 } + (s.marks.isEmpty ? [] : ["after " + s.marks.joined(separator: " → ")])).joined(separator: " · "))
        }
        rows += r.events.filter { $0.kind != "freeze" && $0.kind != "hang" }.map { e in
            Row(at: e.at, time: time(e.at), title: e.kind == "renderer" ? "Page process \(e.detail)" : "Load failed (\(e.detail))",
                detail: e.site ?? "")
        }
        return rows.sorted { $0.at > $1.at }
    }

    // MARK: Export

    @ViewBuilder private func export(_ hideSites: Binding<Bool>) -> some View {
        SettingsCard {
            SettingsCardRow {
                Text("Hide site names").font(.system(size: 13))
            } trailing: {
                Toggle("Hide site names", isOn: hideSites).toggleStyle(.switch).labelsHidden()
            }
        }
        SettingsFootnote("Sites in the exported files become site-1, site-2… in every file, logs included. Without it they keep their host name (never the full address), as Cra's logs always have.")
        HStack(spacing: 8) {
            Button("Export Diagnostics…") { actions.exportDiagnostics() }
            Button(copied ? "Copied" : "Copy Summary") {
                guard let r = report else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(PerfSummary.text(r), forType: .string)
                copied = true
            }
            .disabled(report == nil)
            Spacer(minLength: 0)
            Button("Clear…") { confirmClear() }
        }
        .padding(.top, 16)
        SettingsFootnote("Copy Summary never names a site. The recording lives in \(AppPaths.file("Perf").path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) and stays under 2 MB.")
            .padding(.top, 4)
    }

    private func confirmClear() {
        let alert = AppDialog(title: "Clear the performance recording?",
                              message: "This session's numbers, the last 24 hours and saved freezes are deleted.",
                              actions: [DialogAction("Clear", role: .destructive), .cancel])
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        PerfRecorder.clear()
        report = nil
    }
}

private extension PerfProcessKind {
    var label: String {
        switch self {
        case .browser: return "Cra"
        case .renderer: return "Pages"
        case .gpu: return "GPU"
        case .utility: return "Network, storage, audio"
        case .other: return "Other"
        }
    }
}
