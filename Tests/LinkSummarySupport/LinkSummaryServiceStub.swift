import AppKit

// What LinkSummaryPreview.swift needs from the app, without Chromium or the model.
enum CraLog { static func note(_ s: String) {} }

@MainActor final class LinkSummaryService {
    static let shared = LinkSummaryService()
    struct Card { var title: String; var host: String; var image: NSImage?; var result: LinkSummaryResult?; var finished = false }
    func cached(_ link: URL) -> Card? { nil }
    func load(link: URL, profilePath: String?, httpsOnly: Bool, searchQuery: String?, update: @escaping (Card) -> Void) async {}
    func title(link: URL, profilePath: String?, httpsOnly: Bool) async -> String? { nil }
}
