import AppKit
import Observation

/// Puts the screenshots the system takes into the downloads list by themselves, as Arc's Library
/// button did (`ScreenshotFeed`). Spotlight finds them by macOS's screen-capture mark, live, in the
/// home folder and the screenshot folder (Screenshot ▸ Options ▸ Save to). Cra reads no folder to
/// list them, so a launch asks macOS for nothing (#757).
@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private weak var store: SidebarStore?
    private var shots: [ScreenshotFeed.Shot] = []
    private var refresh: ScheduledWork?
    private var scheduler: Scheduler = LiveScheduler.shared

    func start(store: SidebarStore, scheduler: Scheduler = LiveScheduler.shared) {
        guard self.store == nil else { return }
        self.store = store
        self.scheduler = scheduler
        DownloadHistory.shared.hideScreenshot = { [weak store] path in
            guard let store, !store.settings.mediaHidden.contains(path) else { return }
            store.settings.mediaHidden.append(path)
        }
        observeChanges(of: { [weak store] in
            Pair(folders: store?.settings.mediaFolders ?? [], hidden: store?.settings.mediaHidden ?? [])
        }) { [weak self] pair in
            self?.settingsChanged(folders: pair.folders)
        }
        // The list's day moves on: what aged out leaves it.
        refresh = scheduler.every(15 * 60) { [weak self] in self?.publish() }
    }

    private struct Pair: Equatable {
        var folders: [MediaLibrary.Folder]
        var hidden: [String]
    }

    private func settingsChanged(folders: [MediaLibrary.Folder]) {
        if ScreenshotFeed.enabled(folders: folders) {
            if query == nil { restartQuery() } else { publish() }
        } else {
            stopQuery()
            publish()
        }
    }

    /// Spotlight leaves out what macOS doesn't let Cra read, without asking: screenshots on the
    /// Desktop (where the system saves them unless Screenshot ▸ Options says otherwise) stay hidden
    /// until Cra may read the Desktop. Opening the Library is when Cra reads the screenshot folder,
    /// once a launch, so macOS asks that the first time (as Arc's Library did, Show Media's question
    /// in Arc 1.172.1) and never at launch (#757). Granted, the screenshots there join the list.
    private var askedThisLaunch = false

    func libraryOpened() {
        guard !askedThisLaunch, let store, ScreenshotFeed.enabled(folders: store.settings.mediaFolders),
              let folder = Self.screenshotFolder else { return }
        askedThisLaunch = true
        Task.detached(priority: .utility) {
            let readable = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
            await MainActor.run {
                CraLog.note("screenshot folder readable: \(readable)")
                if readable { ScreenshotWatcher.shared.restartQuery() }
            }
        }
    }

    /// The screenshot folder, the Desktop unless Screenshot ▸ Options says otherwise.
    static var screenshotFolder: URL? { MediaScanner.url(.screenshots) }

    private func restartQuery() {
        guard let store, ScreenshotFeed.enabled(folders: store.settings.mediaFolders) else { return }
        stopQuery()
        let since = Date().addingTimeInterval(-ScreenshotFeed.window)
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", since as NSDate)
        var scopes: [Any] = [NSMetadataQueryUserHomeScope]
        if let folder = Self.screenshotFolder, !folder.path.hasPrefix(NSHomeDirectory() + "/") { scopes.append(folder) }
        q.searchScopes = scopes
        q.notificationBatchingInterval = 0.3
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: q, queue: .main) { _ in
                MainActor.assumeIsolated { ScreenshotWatcher.shared.collect() }
            })
        }
        query = q
        q.start()
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        shots = []
    }

    private func collect() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var found: [ScreenshotFeed.Shot] = []
        for case let item as NSMetadataItem in q.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let date = item.value(forAttribute: "kMDItemFSCreationDate") as? Date
                ?? item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            found.append(.init(path: path, date: date))
        }
        shots = found
        publish()
    }

    private func publish() {
        guard let store else { return }
        let entries = ScreenshotFeed.entries(shots, enabled: ScreenshotFeed.enabled(folders: store.settings.mediaFolders),
                                             hidden: Set(store.settings.mediaHidden), downloads: DownloadHistory.shared.entries,
                                             now: scheduler.now)
        if entries != DownloadHistory.shared.screenshots {
            DownloadHistory.shared.screenshots = entries
            CraLog.note("screenshots in the downloads list: \(entries.count)")
        }
    }

    /// For the `downloads-tray-screenshots` scenario: a picture as the system's screenshot tool saves
    /// one (the `com.apple.metadata:kMDItemIsScreenCapture` mark), where Spotlight indexes it. A name
    /// starting with "-" deletes that picture instead.
    static func writeFakeScreenshot(named name: String) {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        if name.hasPrefix("-") {
            try? FileManager.default.removeItem(at: pictures.appendingPathComponent(String(name.dropFirst())))
            return
        }
        let url = pictures.appendingPathComponent((name as NSString).lastPathComponent)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let png = image?.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil,
              let mark = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0) else {
            CraLog.note("fake screenshot: could not write \(url.path)")
            return
        }
        _ = mark.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, mark.count, 0, 0) }
        CraLog.note("fake screenshot: \(url.lastPathComponent)")
    }
}
