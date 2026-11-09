import Foundation

public struct LiveFolderPluginConfiguration: Codable, Equatable {
    public static func normalizedAddress(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var url = URLComponents(string: text.contains("://") ? text : "https://\(text)"),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        url.scheme = url.scheme?.lowercased()
        url.host = host.lowercased()
        if (url.scheme == "https" && url.port == 443) || (url.scheme == "http" && url.port == 80) { url.port = nil }
        if let port = url.port, !(1...65535).contains(port) { return nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        return url.url?.absoluteString
    }
    public var id: String
    public var settings: [String: String]
    public var filters: [String]
    public var state: [String: String]
    public var sessionOrigins: [String]
    public var snapshot: LiveFolderPluginSnapshot?
    public var snapshotFilters: [String]?
    public var signIn: LiveFolderPluginSnapshot.Action?
    public var signInWarning: String?
    public var emptyText: String?
    public var failureText: String?
    public var failureURL: String?
    public var instanceLabel: String?
    public var detailLabel: String?

    public init(id: String, settings: [String: String], filters: [String],
                state: [String: String] = [:], sessionOrigins: [String]) {
        self.id = id
        self.settings = settings
        self.filters = filters
        self.state = state
        self.sessionOrigins = sessionOrigins
    }
}
