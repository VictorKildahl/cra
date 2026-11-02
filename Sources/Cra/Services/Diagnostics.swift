import AppKit
import CraCEF
import UniformTypeIdentifiers

/// Help ▸ Export Diagnostics…: a zip a user can attach to an issue or send by mail. Holds
/// Cra's and Chromium's logs (this launch and the last), the on-screen pages' state, the GPU
/// report and recent crash reports. Addresses are cut to their host and the home folder to
/// `~`; no history, cookies, passwords or page content leave the Mac.
@MainActor
enum Diagnostics {
    /// Asks where to save, unless `destination` is given (cra://debug?exportDiagnostics=<path>).
    static func export(windows: [MainWindowController], store: SidebarStore, to destination: URL? = nil) {
        CraLog.note("diagnostics export started")
        collectPages(windows: windows, store: store) { pages in
            CraCEFRuntime.sendBrowserDevToolsMethod("SystemInfo.getInfo", params: "{}") { gpu, error in
                DispatchQueue.main.async {
                    save(pages: pages, gpu: gpu ?? "{\"error\": \"\(error ?? "no answer")\"}", store: store, to: destination)
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

    private static func save(pages: String, gpu: String, store: SidebarStore, to chosen: URL?) {
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
        func write(_ text: String, _ file: String) {
            try? Data(DiagnosticsRedaction.redact(text, home: home).utf8).write(to: folder.appendingPathComponent(file))
        }

        CraLog.flush()
        write(summary(store: store), "summary.txt")
        write(pages, "pages.txt")
        write(gpu, "gpu.json")
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
            let alert = NSAlert()
            alert.messageText = "Cra couldn’t save the diagnostics"
            alert.informativeText = "Try another folder."
            alert.runModal()
            return
        }
        CraLog.note("diagnostics exported (\(crashes.count) crash reports)")
        if chosen == nil { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
    }

    private static func askWhere(_ fileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.message = "Cra's logs, the state of the pages on screen and recent crash reports. Site names only: no addresses, history, cookies or passwords."
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
        return lines.joined(separator: "\n") + "\n"
    }
}
