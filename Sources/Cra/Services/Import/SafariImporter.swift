import Foundation

// Safari keeps its data behind Full Disk Access, so Dia imports what Safari
// exports itself (File ▸ Export Browsing Data to File…): a .zip, or the folder
// it unpacks to, holding Bookmarks.html, History.json and Passwords.csv.
// Dia's SafariExportedDataView takes the file by drop or by file panel.

struct SafariExport {
    var plan: ImportPlan
    var logins: [ImportedLogin]
    var topSites: [TopSite]
}

enum SafariExportError: LocalizedError {
    case unsupported, missingFiles, invalid
    // Dia's SafariExportedDataValidator messages.
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Please select a folder or zip file."
        case .missingFiles: return "The folder is missing required files. Please try again."
        case .invalid: return "The selected file is invalid. Please try again."
        }
    }
}

enum SafariImporter {
    static let names = ["Bookmarks.html", "History.json", "Passwords.csv"]

    /// Reads an exported .zip (unpacked with ditto into a temporary folder) or folder.
    static func read(_ url: URL) throws -> SafariExport {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { throw SafariExportError.invalid }
        var folder = url
        var temp: URL?
        defer { if let temp { try? fm.removeItem(at: temp) } }
        if !isDir.boolValue {
            guard url.pathExtension.lowercased() == "zip" else { throw SafariExportError.unsupported }
            let dest = fm.temporaryDirectory.appendingPathComponent("cra-safari-\(UUID().uuidString)", isDirectory: true)
            temp = dest
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-x", "-k", url.path, dest.path]
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw SafariExportError.invalid }
            folder = dest
        }
        // The archive may wrap everything in one folder.
        guard let root = locate(in: folder) else { throw SafariExportError.missingFiles }
        var plan = ImportPlan(source: "Safari")
        if let html = try? String(contentsOf: root.appendingPathComponent("Bookmarks.html"), encoding: .utf8) {
            var skipped: [ImportSkip] = []
            let (favorites, folders) = bookmarks(html: html, skip: { skipped.append($0) })
            let pinned = favorites + folders
            if !pinned.isEmpty { plan.spaces.append(ImportedSpace(title: "Safari", emoji: "🧭", theme: nil, pinned: pinned, skipped: skipped)) }
            else { plan.skipped = skipped }
        }
        let logins = (try? String(contentsOf: root.appendingPathComponent("Passwords.csv"), encoding: .utf8)).map(PasswordCSV.logins) ?? []
        let sites = (try? Data(contentsOf: root.appendingPathComponent("History.json"))).map { topSites($0) } ?? []
        if plan.spaces.isEmpty && logins.isEmpty && sites.isEmpty { throw SafariExportError.missingFiles }
        return SafariExport(plan: plan, logins: logins, topSites: sites)
    }

    private static func locate(in folder: URL) -> URL? {
        let fm = FileManager.default
        func has(_ dir: URL) -> Bool { names.contains { fm.fileExists(atPath: dir.appendingPathComponent($0).path) } }
        if has(folder) { return folder }
        let subs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return subs.first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && has($0) }
    }

    /// Netscape bookmark file: `<DT><H3>` opens a folder whose items follow in
    /// a `<DL>`, `<DT><A HREF>` is a bookmark. Safari's Favorites folder becomes
    /// the pinned list; the Reading List is left out. `skip` hears of each bookmark left out.
    static func bookmarks(html: String, skip: (ImportSkip) -> Void = { _ in }) -> (favorites: [ImportedItem], folders: [ImportedItem]) {
        let pattern = #"<DT><H3[^>]*>(.*?)</H3>|<DT><A [^>]*HREF="([^"]*)"[^>]*>(.*?)</A>|</DL>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return ([], []) }
        // Stack of open folders; the bottom one is the file's root.
        var stack: [(name: String, items: [ImportedItem])] = [("", [])]
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                stack.append((unescape(ns.substring(with: m.range(at: 1))), []))
            } else if m.range(at: 2).location != NSNotFound {
                let url = unescape(ns.substring(with: m.range(at: 2)))
                let title = unescape(ns.substring(with: m.range(at: 3)))
                guard ImportedAddress.keeps(url) else {
                    // The Reading List stays out whole, so nothing in it is listed.
                    if stack.count < 2 || stack[1].name.lowercased() != "reading list" { ImportSkip.leftOut(url, title: title).map(skip) }
                    continue
                }
                stack[stack.count - 1].items.append(ImportedItem(customTitle: title.isEmpty ? nil : title, pageTitle: title, url: url))
            } else if stack.count > 1 {
                let done = stack.removeLast()
                if !done.items.isEmpty {
                    stack[stack.count - 1].items.append(ImportedItem(customTitle: done.name, pageTitle: done.name, url: nil, isFolder: true, children: done.items))
                }
            }
        }
        while stack.count > 1 {
            let done = stack.removeLast()
            if !done.items.isEmpty { stack[stack.count - 1].items.append(ImportedItem(customTitle: done.name, pageTitle: done.name, url: nil, isFolder: true, children: done.items)) }
        }
        var favorites: [ImportedItem] = [], folders: [ImportedItem] = []
        for item in stack[0].items {
            let name = item.pageTitle.lowercased()
            if item.isFolder && ["favorites", "favourites", "favorites bar", "favourites bar"].contains(name) { favorites += item.children }
            else if item.isFolder && name == "reading list" { continue }
            else if item.isFolder { folders.append(item) }
            else { favorites.append(item) }
        }
        return (favorites, folders)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// History.json: {"history": [{"url", "title", "visit_count"}, …]}.
    static func topSites(_ data: Data, limit: Int = 24) -> [TopSite] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["history"] as? [[String: Any]] else { return [] }
        var byHost: [String: TopSite] = [:]
        for e in entries {
            guard let u = e["url"] as? String,
                  let site = TopSite(url: u, title: e["title"] as? String ?? "", visits: e["visit_count"] as? Int ?? 1) else { continue }
            byHost[site.host, default: TopSite(host: site.host, url: site.url, title: site.title, visits: 0)].visits += site.visits
        }
        return Array(byHost.values.sorted { $0.visits > $1.visits }.prefix(limit))
    }
}
