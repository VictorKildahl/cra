import Foundation

/// One of Chrome's bars over a page ("<extension> started debugging this browser", GitHub #241), as the Chromium
/// engine reports them (CraBrowser.infoBars): Cra draws them itself, since Chrome would draw them in its
/// never-shown window. On CEF Chrome draws its own and none are reported.
public struct PageInfoBar: Equatable, Sendable {
    public var id: Int
    public var message: String
    /// The buttons' titles, in Chrome's order (OK first), and the link's.
    public var ok: String?
    public var cancel: String?
    public var link: String?
    /// It has a ✕.
    public var closeable: Bool

    public init(id: Int, message: String, ok: String? = nil, cancel: String? = nil, link: String? = nil, closeable: Bool = true) {
        self.id = id
        self.message = message
        self.ok = ok
        self.cancel = cancel
        self.link = link
        self.closeable = closeable
    }

    /// A bar from the bridge's dictionary; nil without an id or a message. Empty titles count as none.
    public init?(_ entry: [String: Any]) {
        guard let id = (entry["id"] as? NSNumber)?.intValue ?? entry["id"] as? Int,
              let message = entry["message"] as? String, !message.isEmpty else { return nil }
        func title(_ key: String) -> String? { (entry[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        self.init(id: id, message: message, ok: title("ok"), cancel: title("cancel"), link: title("link"),
                  closeable: (entry["closeable"] as? NSNumber)?.boolValue ?? entry["closeable"] as? Bool ?? true)
    }

    /// Chrome's infobar height, each bar stacked above the page.
    public static let height: Double = 40

    /// What the bars take from the top of the page.
    public static func inset(for bars: [PageInfoBar]) -> Double { Double(bars.count) * height }
}
