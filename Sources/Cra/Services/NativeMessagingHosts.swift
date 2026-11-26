import Foundation

/// Extensions that talk to a desktop app (1Password, Bitwarden, Claude, Notion…)
/// find it through a native messaging host manifest. Apps install those into the
/// browsers they know, never into Cra's profile, so Chromium logs "Can't find
/// manifest for native messaging host" and the extension stays disconnected.
/// Before Chromium starts, Cra links the manifests into its own NativeMessagingHosts
/// folder. Links, not copies: an app that rewrites its manifest on update is picked
/// up without Cra noticing.
///
/// The manifests come from the system-wide folders and from the browsers the person
/// imported from (imported-browsers.json), never from a browser's folder Cra wasn't
/// asked to read: macOS can keep Chrome's and Brave's folders from other apps, and
/// reading them at launch showed "Data Access Blocked" on Cra's first launch (#757).
/// For apps that install only into browsers they know (1Password), Cra writes the
/// manifest itself when the app is installed and no browser's was linked (#847).
enum NativeMessagingHosts {
    static func link(into profileRoot: URL) {
        let fm = FileManager.default
        let dest = profileRoot.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let ownLinks = ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []).map { dest.appendingPathComponent($0) }
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
        let imported = importedBrowsers(migratingFrom: ownLinks)

        // Rebuilt every launch, so hosts that were uninstalled go away. Plain
        // files are someone's own manifests and stay.
        for link in ownLinks { try? fm.removeItem(at: link) }

        // First source wins: Chrome is where every app installs, the rest fill gaps.
        let folders = OtherBrowserData.nativeMessagingFolders(browsers, imported: imported, system: systemFolders)
        for dir in folders.map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".json") && !excluded.contains(name) {
                let link = dest.appendingPathComponent(name)
                if (try? link.checkResourceIsReachable()) == true { continue }
                try? fm.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent(name))
            }
        }

        // Apps that install their manifest only into browsers they know (1Password): with the app installed and no
        // browser's manifest linked above, Cra writes it into its own folder and links that (KnownNativeHosts, #847).
        let linked = Set((try? fm.contentsOfDirectory(atPath: dest.path)) ?? [])
        let known = AppPaths.file("KnownNativeHosts")
        for manifest in KnownNativeHosts.manifests(linked: linked, exists: { fm.isExecutableFile(atPath: $0) }) {
            try? fm.createDirectory(at: known, withIntermediateDirectories: true)
            let file = known.appendingPathComponent(manifest.file)
            if (try? Data(contentsOf: file)) != manifest.data { try? manifest.data.write(to: file, options: .atomic) }
            try? fm.createSymbolicLink(at: dest.appendingPathComponent(manifest.file), withDestinationURL: file)
        }
    }

    /// The person started an import from `source`: Cra may read its folder from now on, so its
    /// manifests link at once (Chromium reads them each time an extension connects) and at
    /// every launch after.
    static func recordImport(from source: ImportSource, into profileRoot: URL) {
        let before = importedBrowsers()
        let after = before.adding(source.id)
        guard after != before else { return }
        save(after)
        link(into: profileRoot)
    }

    /// The browsers imported from. Cra from before #757 had no such file and linked every
    /// browser's manifests: the browsers its links still point into count as imported from.
    /// The launch-time link passes Cra's own links (`migratingFrom`) and writes the result, so the
    /// file exists from the first launch on.
    static func importedBrowsers(migratingFrom links: [URL]? = nil) -> ImportedBrowsers {
        if let data = try? Data(contentsOf: importedFile),
           let list = try? JSONDecoder().decode(ImportedBrowsers.self, from: data) { return list }
        guard let links else { return ImportedBrowsers() }
        let targets = links.compactMap { try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path) }
        let migrated = ImportedBrowsers.migrated(linkTargets: targets, browsers: browsers)
        save(migrated)
        return migrated
    }

    private static var importedFile: URL { AppPaths.file("imported-browsers.json") }

    private static func save(_ list: ImportedBrowsers) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: importedFile, options: .atomic)
    }

    /// Hosts that let a desktop app drive "Chrome" through its extension. The app
    /// cannot tell Cra from Chrome, so ChatGPT's computer use switched to Cra (and
    /// its agent tabs took over Cra's window) instead of using the user's Chrome.
    private static let excluded: Set<String> = [
        "com.openai.codexextension.json",   // ChatGPT desktop app → ChatGPT extension
    ]

    private static var browsers: [OtherBrowserData.Browser] {
        ImportSource.allCases.filter { [.chromium, .arc, .dia].contains($0.kind) }.map(\.otherBrowser)
    }

    /// System-wide installs (all users), per browser; macOS doesn't keep these from other apps.
    private static let systemFolders = [
        "/Library/Google/Chrome/NativeMessagingHosts",
        "/Library/Application Support/Chromium/NativeMessagingHosts",
        "/Library/Microsoft/Edge/NativeMessagingHosts",
        "/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts",
    ]
}
