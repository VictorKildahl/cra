import CoreGraphics
import Foundation

/// What Arc Search 1.49 says about its blockers on the page itself (Victor's recording, 1:59 and
/// 3:20): a one-time tip card when blocking first stops something, and after "Problems? Tap to
/// restore original page" a pill asking whether that fixed it.
public enum MobileBlockerNotices {
    // MARK: The tip card ("TIP 1/7" in Arc Search; Cra has only this tip, so its tab says "TIP")

    /// The card shows once ever: on the first page that finished loading with something stopped,
    /// never in an incognito tab.
    public static func showsTip(blocked: Int, alreadyShown: Bool, isIncognito: Bool) -> Bool {
        blocked > 0 && !alreadyShown && !isIncognito
    }

    /// "Cra just blocked 14 trackers": the text, and the number Arc Search draws in blue.
    public static func tipTitle(_ count: Int) -> (text: String, number: String) {
        let number = String(max(count, 0))
        return ("Cra just blocked \(number) \(count == 1 ? "tracker" : "trackers")", number)
    }

    /// Before and after the ⌃ glyph (drawn as the bar's chevron).
    public static let tipDetail = (before: "See more and change block settings in the", after: "menu")
    public static let tipTab = "TIP"

    /// Measured on the recording (3 px per point, 440 pt wide): 20 pt in from the sides, 92 pt
    /// tall, its bottom 4 pt into the bar; the tab 66 × 22 pt, 5 pt above the card.
    public static let tipInset: CGFloat = 20
    public static let tipHeight: CGFloat = 92
    public static let tipOverlap: CGFloat = 4
    public static let tipCornerRadius: CGFloat = 20
    public static let tipTabSize = CGSize(width: 50, height: 22)
    public static let tipTabGap: CGFloat = 5

    // MARK: The pill after the page was restored

    public static let fixQuestion = "Did it fix the issue?"

    /// The pill's answer to a thumbs-up: the site keeps no blockers from now on.
    public static func disabledLabel(site: String) -> String { "Blockers disabled for \(site)" }

    /// 48 pt tall with 17 pt corners, centred on the bar's + (the recording: 254 pt with the
    /// question and its two 33 pt thumbs, 280 pt with "Blockers disabled for google.com").
    public static let pillHeight: CGFloat = 48
    public static let pillCornerRadius: CGFloat = 17
    public static let thumbSize: CGFloat = 33
    public static let thumbSpacing: CGFloat = 8
    /// The gradient's top and bottom, sampled: #4D5FFC to #2D45E1.
    public static let pillTop: UInt32 = 0x4d5ffc
    public static let pillBottom: UInt32 = 0x2d45e1
}

extension MobileSettings {
    /// A thumbs-up on "Did it fix the issue?": the site's three blockers go off, kept like any
    /// other Site Settings choice.
    public mutating func disableBlockers(for host: String) {
        var options = options(for: host)
        options.blockAds = false
        options.blockCookieBanners = false
        options.blockTrackers = false
        setOptions(options, for: host)
    }
}
