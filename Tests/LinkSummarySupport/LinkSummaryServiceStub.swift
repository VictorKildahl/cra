import AppKit

// What LinkSummaryPreview.swift needs from the app, without Chromium or the model.
enum CraLog { static func note(_ s: String) {} }

@MainActor final class LinkSummaryService {
    static let shared = LinkSummaryService()
    struct Card { var title: String; var host: String; var image: NSImage?; var result: LinkSummaryResult?; var finished = false }
    static func request(link: URL, profilePath: String?, httpsOnly: Bool, searchQuery: String?) -> LinkSummaryRequest {
        LinkSummaryRequest(link: link, profilePath: profilePath, httpsOnly: httpsOnly, searchQuery: searchQuery, language: "English")
    }
    func cached(_ request: LinkSummaryRequest) -> Card? { nil }
    func load(_ request: LinkSummaryRequest, update: @escaping (Card) -> Void) async {}
    func title(_ request: LinkSummaryRequest) async -> String? { nil }
}
