import AppKit
import Security

/// Keeps an old copy of Cra from standing in for a new one. Chromium lets one process
/// own the profile and hands every later launch to it, so a new download opened while
/// an old Cra is still running (closed windows, launch at login) used to show the old
/// version. Finder cannot replace a running app either, which leaves "Cra 2.app" next
/// to the old Cra.app that the Dock and login items keep opening. Both run from
/// main.swift before Chromium starts.
enum NewestCopy {
    static let version = shortVersion(at: Bundle.main.bundleURL) ?? ""

    /// Numeric, so 0.1.10 is newer than 0.1.9 and 0.0.0-dev is older than any release.
    static func isOlder(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }

    /// Read from disk rather than through Bundle, which caches Info.plist per path.
    static func shortVersion(at bundle: URL) -> String? {
        NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    /// An installed release opened while a newer one sits elsewhere on the Mac opens that
    /// one and exits. Only signed releases on the default data dir take part: dev builds
    /// (0.0.0-dev, no SUFeedURL) and CRA_DATA_DIR copies must run as themselves.
    static func openNewerInstalledCopy() {
        guard ProcessInfo.processInfo.environment["CRA_DATA_DIR"] == nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              let id = Bundle.main.bundleIdentifier, let team = teamID(of: Bundle.main.bundleURL) else { return }
        let me = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let newer = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id)
            .map { $0.resolvingSymlinksInPath() }
            .filter { $0.path != me && isInstalled($0) }
            .compactMap { url in shortVersion(at: url).map { (url: url, version: $0) } }
            .filter { isOlder(version, than: $0.version) && teamID(of: $0.url) == team }
            .max { isOlder($0.version, than: $1.version) }
        guard let newer else { return }
        NSLog("Cra: \(version) at \(me) opens the newer \(newer.version) at \(newer.url.path)")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [newer.url.path]
        guard (try? open.run()) != nil else { return }
        open.waitUntilExit()
        if open.terminationStatus == 0 { exit(0) }
    }

    /// A running Cra older than this one that owns our profile is asked to quit, so this
    /// launch takes over instead of being handed to it. Its SingletonLock names it
    /// ("host-pid"), which also leaves CRA_DATA_DIR copies on other profiles alone.
    @MainActor static func replaceOlderRunningCopy() {
        guard let other = profileOwner(), let url = other.bundleURL,
              let theirs = shortVersion(at: url), isOlder(theirs, than: version) else { return }
        let pid = other.processIdentifier
        NSLog("Cra: \(version) replaces the running \(theirs) (pid \(pid))")
        other.terminate()
        while !waitForExit(pid, seconds: 10) {
            switch stillOpenAlert(theirs, pid: pid) {
            case .OK: break
            case .alertFirstButtonReturn: other.terminate()
            case .alertSecondButtonReturn: other.forceTerminate()
            default: other.activate(); exit(0)
            }
        }
        // As in relaunch(): give Chromium a moment to let go of the profile.
        usleep(300_000)
    }

    /// Shown when the old copy has not quit, usually because its "Warn before quitting"
    /// prompt is up. That prompt is centred and its app is in front, so this one floats
    /// above the centre and stays visible while Cra is not active (the launch may not
    /// have activated it yet), and it closes by itself (.OK) once the old copy is gone.
    @MainActor private static func stillOpenAlert(_ theirs: String, pid: pid_t) -> NSApplication.ModalResponse {
        let alert = AppDialog(title: "Cra \(theirs) is still open",
                              message: "Quit it to open Cra \(version). If it asked whether to quit, choose Quit.",
                              actions: [DialogAction("Try Again"), DialogAction("Force Quit", role: .destructive), .cancel])
        let window = alert.prepareWindow()
        window.hidesOnDeactivate = false
        if let screen = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY + 170))
        }
        // runModal resets the level, so raise it once the modal session runs.
        RunLoop.current.perform(inModes: [.modalPanel]) {
            MainActor.assumeIsolated {
                window.level = .floating
                window.orderFrontRegardless()
            }
        }
        let gone = Timer(timeInterval: 0.2, repeats: true) { _ in
            if kill(pid, 0) != 0 && errno == ESRCH { MainActor.assumeIsolated { NSApp.stopModal(withCode: .OK) } }
        }
        RunLoop.current.add(gone, forMode: .modalPanel)
        defer { gone.invalidate() }
        return alert.runModal(over: nil)
    }

    private static func profileOwner() -> NSRunningApplication? {
        let lock = AppPaths.chromiumCache.appendingPathComponent("SingletonLock").path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock),
              let pid = target.split(separator: "-").last.flatMap({ pid_t($0) }), pid != getpid(),
              let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == Bundle.main.bundleIdentifier else { return nil }
        return app
    }

    private static func waitForExit(_ pid: pid_t, seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while kill(pid, 0) == 0 || errno != ESRCH {
            if Date() > deadline { return false }
            usleep(100_000)
        }
        return true
    }

    /// Not a disk image, the Trash or a translocated copy, which are not installs.
    private static func isInstalled(_ url: URL) -> Bool {
        let p = url.path
        return FileManager.default.fileExists(atPath: p) && !p.hasPrefix("/Volumes/")
            && !p.contains("/.Trash/") && !p.contains("/AppTranslocation/")
    }

    /// The signing team, checked without hashing every resource (CEF is large);
    /// Gatekeeper checks the whole bundle when it opens. nil for ad-hoc builds.
    private static func teamID(of bundle: URL) -> String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
