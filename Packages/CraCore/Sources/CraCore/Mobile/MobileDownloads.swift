import Foundation

/// `downloads.json` in the iPhone app's data folder: what was downloaded, newest first. The files
/// themselves are in the app's Documents/Downloads, which the Files app shows.
public struct MobileDownloads: Codable, Equatable {
    public struct Item: Codable, Equatable, Identifiable {
        public var id: UUID
        /// The file's name in the Downloads folder.
        public var name: String
        public var source: String
        public var date: Date
        public var bytes: Int64

        public init(id: UUID = UUID(), name: String, source: String, date: Date, bytes: Int64) {
            self.id = id
            self.name = name
            self.source = source
            self.date = date
            self.bytes = bytes
        }
    }

    public var items: [Item] = []

    public init() {}

    private enum CodingKeys: String, CodingKey { case items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
    }

    public mutating func add(_ item: Item) {
        items.insert(item, at: 0)
    }

    public mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    /// A name no file in the folder has yet. Arc Search numbers a repeated download instead of
    /// overwriting it: "report.pdf", then "report 2.pdf", "report 3.pdf".
    public static func freeName(for suggested: String, taken: Set<String>) -> String {
        let clean = safeName(suggested)
        guard taken.contains(clean) else { return clean }
        let url = URL(fileURLWithPath: clean)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? clean : String(clean.dropLast(ext.count + 1))
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// A file name with nothing that could leave the folder or hide the file.
    public static func safeName(_ suggested: String) -> String {
        var name = suggested.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "Download" : name
    }

    /// A row's second line: where it came from and how big it is.
    public static func detail(for item: Item) -> String {
        let host = URL(string: item.source)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        let size = ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)
        return host.isEmpty ? size : "\(host) · \(size)"
    }

    public enum Opening: Equatable {
        /// A Wallet pass: offered to Wallet.
        case walletPass
        /// Anything else: previewed.
        case preview
    }

    public static func opening(forName name: String) -> Opening {
        URL(fileURLWithPath: name).pathExtension.lowercased() == "pkpass" ? .walletPass : .preview
    }
}

/// What the page's certificate warning says, and for which hosts the user chose to go on anyway.
public struct MobileCertificateExceptions: Equatable {
    public private(set) var hosts: Set<String> = []

    public init() {}

    public mutating func allow(_ host: String) {
        hosts.insert(host.lowercased())
    }

    /// The exception is for that host alone, and lasts until the app quits.
    public func allows(_ host: String) -> Bool {
        hosts.contains(host.lowercased())
    }

    public static func warningTitle(host: String) -> String { "This connection is not private" }

    public static func warningMessage(host: String) -> String {
        "Cra can't verify the identity of \(host). Someone may be pretending to be this site. Go on only if you know why its certificate can't be checked."
    }
}
