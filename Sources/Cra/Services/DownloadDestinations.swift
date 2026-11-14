import AppKit
import CraCEF

/// Where a download is saved (GitHub #190): the profile's Download location from Settings ▸
/// Profiles (Arc keeps one per profile), or a save panel when that profile asks for each file.
/// CEF pages come in through CraCEFRuntime's download destination handler, WebKit pages
/// through WebKitBrowser.
@MainActor
enum DownloadDestinations {
    private static weak var store: SidebarStore?

    static func install(store: SidebarStore) {
        self.store = store
        CraCEFRuntime.setDownloadDestinationHandler { profilePath, name, completion in
            MainActor.assumeIsolated {
                destination(profilePath: profilePath, suggestedName: name) { completion($0?.path) }
            }
        }
    }

    static var downloadsFolder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    /// The profile a Chromium profile folder belongs to; nil is Default (and off the record).
    static func profileID(profilePath: String?) -> UUID? {
        guard let profilePath else { return nil }
        let dir = URL(fileURLWithPath: profilePath).lastPathComponent
        return store?.profiles.first { $0.directoryName == dir }?.id
    }

    static func location(profileID: UUID?) -> DownloadLocation {
        store?.settings.downloadLocation(profileID: profileID) ?? DownloadLocation()
    }

    /// The folder a profile saves to (the Library's Open Downloads Folder opens it too).
    static func folder(profileID: UUID?) -> URL {
        location(profileID: profileID).folderURL(downloads: downloadsFolder) { path in
            var dir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
        }
    }

    /// The file to save as, or nil when the user cancelled the save panel.
    static func destination(profilePath: String?, suggestedName: String, replaceExisting: Bool = false, completion: @escaping @MainActor (URL?) -> Void) {
        let id = profileID(profilePath: profilePath)
        let folder = folder(profileID: id)
        guard location(profileID: id).askWhereToSave else {
            prepare(DownloadFileName.unique(suggestedName, in: folder) { FileManager.default.fileExists(atPath: $0) }, replacing: false, completion: completion)
            return
        }
        asks.append { done in
            let panel = NSSavePanel()
            panel.directoryURL = folder
            panel.nameFieldStringValue = DownloadFileName.sanitized(suggestedName)
            panel.canCreateDirectories = true
            let finish: (NSApplication.ModalResponse) -> Void = { response in
                MainActor.assumeIsolated {
                    prepare(response == .OK ? panel.url : nil, replacing: replaceExisting, completion: completion)
                    // The sheet is still attached while its handler runs: the next one next turn.
                    DispatchQueue.main.async { done() }
                }
            }
            // On the window the download came from: a page's Chrome-style window is a child of
            // it. Cra in the background has no key or main window: the frontmost of its own.
            var window = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.orderedWindows.first { $0.isVisible && $0.parent == nil && $0.canBecomeMain }
            while let parent = window?.parent { window = parent }
            if let window, window.isVisible, window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: finish)
            } else {
                panel.begin(completionHandler: finish)
            }
        }
        if asks.count == 1 { asks[0](next) }
    }

    /// Both engines reserve before their destination callback can start writing. WebKit also
    /// needs the approved existing file removed; CEF handles that replacement itself.
    static func prepare(_ destination: URL?, replacing: Bool, service: TidyDownloadsService? = nil, completion: @escaping @MainActor (URL?) -> Void) {
        guard let destination else { completion(nil); return }
        let preparation = (service ?? .shared).prepareDestination(destination.path, replacing: replacing)
        Task { @MainActor in completion(await preparation.value ? destination : nil) }
    }

    /// Save panels one at a time: a second download asks once the first panel has closed.
    private static var asks: [(@escaping @MainActor () -> Void) -> Void] = []

    private static func next() {
        asks.removeFirst()
        if let ask = asks.first { ask(next) }
    }
}
