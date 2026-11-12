import CoreGraphics
import Foundation

/// The floating two-part switch on a Browse for Me page and on a search engine's results: Browse
/// for Me on the left, the search engine on the right, the side on screen filled in. Arc Search
/// 1.19 added it ("Toggle at the bottom right of search results pages switches between Google and
/// Browse for Me results"). Measured on TapSmart's March 2025 screenshot (402 pt wide iPhone, 3 px
/// per point): a 108 × 43 pt capsule 16 pt in from the right and 17 pt above the bar, the filled
/// part 42 × 31 pt, 6 pt in from the capsule's left and top.
public enum MobileBrowseToggle {
    public enum Side: Equatable {
        case browseForMe
        case engine
    }

    public static let size = CGSize(width: 108, height: 43)
    public static let rightInset: CGFloat = 16
    /// Capsule bottom to the bar's top edge.
    public static let gapAboveBar: CGFloat = 17
    public static let segmentSize = CGSize(width: 42, height: 31)
    public static let segmentInset: CGFloat = 6

    /// The capsule in a screen `width` wide whose bottom bar's top edge is at `barTop`.
    public static func frame(screenWidth width: CGFloat, barTop: CGFloat) -> CGRect {
        CGRect(x: width - rightInset - size.width, y: barTop - gapAboveBar - size.height,
               width: size.width, height: size.height)
    }

    /// The filled part inside the capsule (capsule coordinates) for the side on screen. The left
    /// one is measured; the right one mirrors it.
    public static func segmentFrame(for side: Side) -> CGRect {
        let x = side == .browseForMe ? segmentInset : size.width - segmentInset - segmentSize.width
        return CGRect(x: x, y: segmentInset, width: segmentSize.width, height: segmentSize.height)
    }

    /// Which side a tab is showing and for what query: a Browse for Me tab (`tabAddress`), or the
    /// engine's results page for a search (`pageURL`). Nil anywhere else, where the switch is hidden.
    public static func state(tabAddress: String, pageURL: String?, engine: MobileSearchEngine) -> (side: Side, query: String)? {
        if let query = MobileBrowseForMe.query(fromTabAddress: tabAddress), !query.isEmpty {
            return (.browseForMe, query)
        }
        if let pageURL, let query = engine.query(fromResultsURL: pageURL) {
            return (.engine, query)
        }
        return nil
    }
}

extension MobileSearchEngine {
    /// The search on one of this engine's results pages, or nil for any other page (another
    /// engine's included: the switch offers the engine the user chose).
    public func query(fromResultsURL address: String) -> String? {
        guard let url = URL(string: address), let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = url.path
        let matches: Bool
        switch self {
        case .google: matches = (host == "google.com" || host.hasPrefix("www.google.") || host.hasPrefix("google.")) && path == "/search"
        case .bing: matches = (host == "www.bing.com" || host == "bing.com") && path == "/search"
        case .duckduckgo: matches = (host == "duckduckgo.com" || host == "html.duckduckgo.com") && (path == "/" || path == "" || path == "/html" || path == "/html/")
        case .ecosia: matches = host == "www.ecosia.org" && path == "/search"
        case .perplexity: matches = host == "www.perplexity.ai" && path == "/search"
        case .kagi: matches = host == "kagi.com" && path == "/search"
        }
        guard matches, let raw = components.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value,
              // A form's + is a space; URLComponents leaves it.
              let query = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding?
                .trimmingCharacters(in: .whitespaces), !query.isEmpty else { return nil }
        return query
    }
}
