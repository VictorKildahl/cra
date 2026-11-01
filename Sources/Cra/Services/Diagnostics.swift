import AppKit
import CraCEF
import UniformTypeIdentifiers

/// Cra's own log, `cra.log` next to Chromium's: what Cra did with each page (opened, shown,
/// loaded, closed) and what the page looked like a moment after it was shown, so a report of
/// a tab that "stays white" can be traced without a debugger. Lines name sites by host only,
/// never the full address: the log is meant to be sent (Help ▸ Export Diagnostics…).
enum CraLog {
    private static let queue = DispatchQueue(label: "dk.kildahl.cra.log", qos: .utility)
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var written = 0
    /// A runaway loop must not fill the disk; a session's log is a few hundred kB.
    private static let limit = 8 << 20

    static var file: URL { AppPaths.file("cra.log") }
    static var previousFile: URL { AppPaths.file("cra.previous.log") }
    static var chromiumPreviousFile: URL { AppPaths.file("chromium.previous.log") }

    /// Before Chromium starts. Only the Cra that owns the data folder rotates: a second launch
    /// that hands its URLs to the running one and quits would move that one's logs away.
    static func startSession(owner: Bool) {
        let fm = FileManager.default
        if owner {
            for (current, previous) in [(file, previousFile), (AppPaths.log, chromiumPreviousFile)] where fm.fileExists(atPath: current.path) {
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: current, to: previous)
            }
        }
        // Above 10: Chromium's DevTools pipe needs descriptors 3 and 4 free (CraCDPPipeSetUp),
        // and this file is opened before Chromium starts.
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        if fd >= 0 {
            let high = fcntl(fd, F_DUPFD_CLOEXEC, 10)
            close(fd)
            if high >= 0 { handle = FileHandle(fileDescriptor: high, closeOnDealloc: true) }
        }
        let info = Bundle.main.infoDictionary
        note("Cra \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) starts, pid \(getpid())\(owner ? "" : ", another Cra owns the data folder")")
    }

    static func note(_ message: String) {
        NSLog("Cra: %@", message)
        let line = "\(timestamp.string(from: Date())) \(message)\n"
        queue.async {
            guard let handle, written < limit, let data = line.data(using: .utf8) else { return }
            written += data.count
            try? handle.write(contentsOf: data)
        }
    }

    /// Waits for lines still being written (before the log is copied).
    static func flush() { queue.sync {} }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Only the host: logs get shared in bug reports.
    static func host(_ url: String) -> String {
        URL(string: url).flatMap { $0.host ?? $0.scheme.map { "\($0):" } } ?? "(no page)"
    }
}

/// What a page holds, asked from the page itself: a blank tab tells apart a navigation that
/// never committed (about:blank), a page Chromium thinks is hidden, one that has content but
/// never painted it, and one that is simply empty.
@MainActor
enum PageProbe {
    private static let script = """
        JSON.stringify({blank: location.href === 'about:blank', ready: document.readyState, visibility: document.visibilityState,
          viewport: innerWidth + 'x' + innerHeight + '@' + devicePixelRatio,
          scrollHeight: document.documentElement ? document.documentElement.scrollHeight : 0,
          elements: document.getElementsByTagName('*').length,
          text: document.body ? document.body.textContent.length : -1,
          painted: performance.getEntriesByName('first-contentful-paint').length > 0})
        """

    /// One line ("ready=complete visibility=visible …"), or why there is none.
    static func run(_ browser: CraBrowser, completion: @escaping (String) -> Void) {
        guard browser.isCreated, !browser.isClosed else { completion("no browser yet"); return }
        let body = try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true])
        var answered = false
        let finish: (String) -> Void = { line in
            guard !answered else { return }
            answered = true
            completion(line)
        }
        // A hung renderer never answers; that is an answer too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish("no answer in 3 s (renderer busy or gone)") }
        browser.sendDevToolsMethod("Runtime.evaluate", params: body.flatMap { String(data: $0, encoding: .utf8) } ?? "{}") { result, error in
            DispatchQueue.main.async {
                guard let data = result?.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let value = (json["result"] as? [String: Any])?["value"] as? String,
                      let fields = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any] else {
                    finish("probe failed: \(error ?? "no result")")
                    return
                }
                finish(["blank", "ready", "visibility", "viewport", "scrollHeight", "elements", "text", "painted"]
                    .map { "\($0)=\(fields[$0].map { "\($0)" } ?? "?")" }.joined(separator: " "))
            }
        }
    }

    /// Where Cra put the page: its view's size and whether anything hides it.
    static func viewState(_ rt: TabRuntime) -> String {
        var views = [rt.browser.containerView]
        if let host = rt.hostWindow {
            views = EmbeddedPages.pageViews(of: host) ?? [host.contentView].compactMap { $0 }
        }
        let shown = views.map { v -> String in
            let hidden = sequence(first: v, next: \.superview).contains { $0.isHidden }
            return "\(Int(v.frame.width))x\(Int(v.frame.height))\(hidden ? " hidden" : "")\(v.window == nil ? " no-window" : "")"
        }
        var s = "view=\(shown.joined(separator: ","))"
        if let host = rt.hostWindow {
            s += " pageWindow=\(host.isVisible ? "visible" : "not visible")\(EmbeddedPages.isHost(host) ? " embedded" : "") alpha=\(host.alphaValue)"
        }
        // Chromium reports a page in a covered window as hidden (visibility=hidden), which is
        // fine; hidden in a window on screen is not.
        if let w = views.first?.window {
            s += " window=\(w.occlusionState.contains(.visible) ? "on screen" : "covered")\(NSApp.isActive ? "" : " app=inactive")"
        }
        return s
    }
}

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
            var s = "Window \(n + 1)\(w.window?.isKeyWindow == true ? " (key)" : ""): \(m.runtimes.count) live pages, frame \(w.window.map { NSStringFromRect($0.frame) } ?? "-")\n"
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
        func write(_ text: String, _ file: String) { try? Data(redact(text).utf8).write(to: folder.appendingPathComponent(file)) }

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
            $0.lastPathComponent.hasPrefix("Cra") && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > weekAgo
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
        let screens = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.backingScaleFactor))x" }
        var lines = [
            "Cra \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))",
            "Chromium \(CraCEFRuntime.chromiumVersion()), CEF \(CraCEFRuntime.cefVersion())",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(String(cString: model)), \(ProcessInfo.processInfo.physicalMemory >> 30) GB, \(ProcessInfo.processInfo.activeProcessorCount) cores",
            "Displays: \(screens.joined(separator: ", "))",
            "Running from: \(Bundle.main.bundlePath)",
            "Up for: \(Int(ProcessInfo.processInfo.systemUptime / 60)) min (Mac), \(Int(-(NSRunningApplication.current.launchDate ?? Date()).timeIntervalSinceNow / 60)) min (Cra)",
            "Embedded pages: \(EmbeddedPages.isEnabled), Chrome-style hosting: \(CraCEFRuntime.chromeHosting())",
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

    /// Addresses keep their scheme and host; the home folder becomes `~`. The single sign-on
    /// hosts IT allowlisted (Chromium's command line in gpu.json) name the user's employer.
    nonisolated static func redact(_ text: String) -> String {
        var s = text.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        for (pattern, template) in [(#"\b((?:https?|wss?|ftp|chrome-extension)://[^/\s"'<>)\]]+)[/?#][^\s"'<>)\]]*"#, "$1/…"),
                                    (#"(--auth-server-allowlist=)[^\s"]+"#, "$1(set by IT)")] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }
}
