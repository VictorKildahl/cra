import AppKit
import CraCEF
import UniformTypeIdentifiers

/// Help ▸ Export Diagnostics…: a zip a user can attach to an issue or send by mail. Holds
/// Cra's and Chromium's logs (this launch and the last), the on-screen pages' state, the GPU
/// report, recent crash reports and the performance recorder's perf.json (GitHub #91).
/// Addresses are cut to their host and the home folder to `~`; with Settings ▸ Performance ▸
/// "Hide site names" the hosts become site-1, site-2… in every file. No history, cookies,
/// passwords or page content leave the Mac.
@MainActor
enum Diagnostics {
    /// Asks where to save, unless `destination` is given (cra://debug?exportDiagnostics=<path>).
    static func export(windows: [MainWindowController], store: SidebarStore, to destination: URL? = nil) {
        CraLog.note("diagnostics export started")
        HitchMonitor.mark("diagnostics-export")
        collectPages(windows: windows, store: store) { pages in
            CraCEFRuntime.sendBrowserDevToolsMethod("SystemInfo.getInfo", params: "{}") { gpu, error in
                // The profile's size is measured off the main thread.
                PerfRecorder.exportFiles { perf, perfSites in
                    save(pages: pages, gpu: gpu ?? "{\"error\": \"\(error ?? "no answer")\"}", perf: perf, perfSites: perfSites,
                         store: store, to: destination)
                }
            }
        }
    }

    private static func collectPages(windows: [MainWindowController], store: SidebarStore, completion: @escaping (String) -> Void) {
        var sections: [String] = []
        var pending: [(String, CraBrowser)] = []
        for (n, w) in windows.enumerated() {
            let m = w.browsers!
            var s = "Window \(n + 1)\(w.window?.isKeyWindow == true ? " (key)" : ""): \(m.runtimes.count) live pages, frame \(w.window.map { NSStringFromRect($0.frame) } ?? "-"), display \(PageProbe.refreshRate(w.window?.screen))\n"
            for id in m.visibleTabIDs {
                let item = store.item(id)
                let incognito = store.isIncognito(item: id)
                let saved = incognito ? "(incognito)" : item?.tab.map { CraLog.host($0.url) } ?? "(no tab)"
                guard let rt = m.runtime(for: id) else { s += "  on screen \(id.uuidString.prefix(8)): \(saved), no page\n"; continue }
                let page = incognito ? "(incognito)" : CraLog.host(rt.browser.currentURL)
                s += "  on screen \(id.uuidString.prefix(8)): sidebar \(saved), page \(page), loading=\(rt.browser.isLoading) \(PageProbe.viewState(rt))\n"
                if !incognito { pending.append(("  probe \(id.uuidString.prefix(8)): ", rt.browser)) }
            }
            s += "\n" + w.embeddedPagesDump()
            sections.append(s)
        }
        var probes: [String] = Array(repeating: "", count: pending.count)
        let group = DispatchGroup()
        for (i, (label, browser)) in pending.enumerated() {
            group.enter()
            PageProbe.run(browser) { probes[i] = label + $0; group.leave() }
        }
        group.notify(queue: .main) {
            completion(sections.joined(separator: "\n") + "\n" + probes.joined(separator: "\n") + "\n")
        }
    }

    private static func save(pages: String, gpu: String, perf: [(name: String, text: String)], perfSites: Set<String>,
                             store: SidebarStore, to chosen: URL?) {
        let stamp: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH.mm"
            return f.string(from: Date())
        }()
        let name = "Cra Diagnostics \(stamp)"
        guard let destination = chosen ?? askWhere(name + ".zip") else { return }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = staging.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let home = NSHomeDirectory()
        var sites = store.settings.perfHidesSiteNames ? SiteNames(hosts: knownSites(store).union(perfSites)) : nil
        func write(_ text: String, _ file: String) {
            var out = DiagnosticsRedaction.redact(text, home: home)
            if sites != nil { out = sites!.apply(out) }
            try? Data(out.utf8).write(to: folder.appendingPathComponent(file))
        }

        CraLog.flush()
        write(summary(store: store), "summary.txt")
        write(pages, "pages.txt")
        write(gpu, "gpu.json")
        if perf.contains(where: { $0.name.hasPrefix("perf/") }) { try? fm.createDirectory(at: folder.appendingPathComponent("perf"), withIntermediateDirectories: true) }
        for (name, text) in perf { write(text, name) }
        for (url, file) in [(CraLog.file, "cra.log"), (CraLog.previousFile, "cra.previous.log"),
                            (AppPaths.log, "chromium.log"), (CraLog.chromiumPreviousFile, "chromium.previous.log")] {
            if let data = try? Data(contentsOf: url) { write(String(decoding: data, as: UTF8.self), file) }
        }
        // macOS writes one for Cra and for each helper (renderer, GPU) that crashed.
        let reports = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        let crashes = ((try? fm.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter {
            DiagnosticsRedaction.isCraCrashReport($0.lastPathComponent) && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > weekAgo
        }
        if !crashes.isEmpty {
            try? fm.createDirectory(at: folder.appendingPathComponent("crashes"), withIntermediateDirectories: true)
            for c in crashes { if let data = try? Data(contentsOf: c) { write(String(decoding: data, as: UTF8.self), "crashes/" + c.lastPathComponent) } }
        }

        try? fm.removeItem(at: destination)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", folder.path, destination.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            CraLog.note("diagnostics export failed: \(error.localizedDescription)")
        }
        try? fm.removeItem(at: staging)
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: destination.path) else {
            let alert = AppDialog(title: "Cra couldn’t save the diagnostics", message: "Try another folder.")
            alert.runModal()
            return
        }
        CraLog.note("diagnostics exported (\(crashes.count) crash reports)")
        if chosen == nil { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
    }

    /// Every site the zip can name: the log's, the sidebar's, the history's and the archive's
    /// (Chromium's log names the sites of the same tabs).
    private static func knownSites(_ store: SidebarStore) -> Set<String> {
        var hosts = CraLog.sitesSeen
        let urls = store.allTabs().compactMap { $0.tab?.url } + store.history.values.map(\.url)
            + store.archive.compactMap { $0.item.tab?.url }
        for u in urls { if let h = SiteNames.siteHost(of: u) { hosts.insert(h) } }
        // The proxy servers extensions set (summary.txt's Proxy section, cra.log).
        for c in ExtensionStore.shared.proxyControllers.values.joined() { hosts.formUnion(c.hosts) }
        return hosts
    }

    private static func askWhere(_ fileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.message = "Cra's logs, its performance record, the state of the pages on screen and recent crash reports. Site names only: no addresses, history, cookies or passwords."
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func summary(store: SidebarStore) -> String {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let displays = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return DisplayDiagnostics(width: Int(screen.frame.width), height: Int(screen.frame.height), scale: Int(screen.backingScaleFactor),
                                      maximumHz: screen.maximumFramesPerSecond,
                                      minimumHz: DisplayDiagnostics.hz(interval: screen.maximumRefreshInterval),
                                      builtIn: CGDisplayIsBuiltin(id) != 0, main: screen == NSScreen.screens.first)
        }
        // Chromium switches part of its window tracking off under Stage Manager (crbug 448103577).
        let stageManager = UserDefaults.standard.persistentDomain(forName: "com.apple.WindowManager")?["GloballyEnabled"] as? Bool ?? false
        var lines = [
            "Cra \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "Chromium \(CraCEFRuntime.chromiumVersion()), CEF \(CraCEFRuntime.cefVersion())",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(String(cString: model)), \(ProcessInfo.processInfo.physicalMemory >> 30) GB, \(ProcessInfo.processInfo.activeProcessorCount) cores",
            DisplayDiagnostics.summary(displays),
            "Stage Manager: \(stageManager ? "on" : "off")",
            // The sidebar goes opaque under it, like AppKit's materials (GitHub #156).
            "Reduce transparency: \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "on" : "off"), increase contrast: \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "on" : "off")",
            "Running from: \(Bundle.main.bundlePath)",
            "Up for: \(Int(ProcessInfo.processInfo.systemUptime / 60)) min (Mac), \(Int(-(NSRunningApplication.current.launchDate ?? Date()).timeIntervalSinceNow / 60)) min (Cra)",
            "Embedded pages: \(EmbeddedPages.isEnabled), Chrome-style hosting: \(CraCEFRuntime.chromeHosting())",
            "Secure DNS: \(CraCEFRuntime.secureDNSMode().map { SecureDNS(mode: $0, templates: CraCEFRuntime.secureDNSTemplates() ?? "").line } ?? "unknown")",
            "",
            "Spaces: \(store.spaces.count), profiles: \(store.profiles.count), tabs: \(store.allTabs().count)",
        ]
        // Sites the user listed (Developer Mode, link routes) are counted, not named.
        if let data = try? JSONEncoder().encode(store.settings),
           var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for key in ["developerHosts", "linkRoutes"] { json[key] = (json[key] as? [Any])?.count }
            if let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                lines += ["", "Settings:", String(decoding: pretty, as: UTF8.self)]
            }
        }
        // Extensions with webRequest or declarativeNetRequest reset page loading when they start
        // (the blank restored tab fixed in 0.1.22), so their permissions are listed too.
        lines += ["", "Extensions:"]
        for e in ExtensionStore.shared.entries {
            let manifest = (try? Data(contentsOf: e.url.appendingPathComponent("manifest.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let permissions = ((manifest?["permissions"] as? [Any]) ?? []).compactMap { $0 as? String }
                .filter { $0.hasPrefix("webRequest") || $0.hasPrefix("declarativeNetRequest") || $0 == "proxy" }
            lines.append("  \(e.name) \(e.version) [\(e.extensionID)]\(e.managedByChrome ? " web store" : "")\(permissions.isEmpty ? "" : " " + permissions.joined(separator: ","))")
        }
        // Two extensions that set the proxy collide quietly (GitHub #107): the one in use and the
        // ones it overrides, per profile.
        lines += ["", "Proxy:"]
        let proxies = ExtensionStore.shared.proxyControllers
        if proxies.isEmpty { lines.append("  not set by an extension") }
        for profile in proxies.keys.sorted() {
            lines.append("  \(profile): " + ExtensionStore.proxyLine(proxies[profile] ?? []))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
