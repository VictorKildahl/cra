import Foundation

/// The iPhone app's icons: the Mac app's four.
public enum MobileAppIcon: String, CaseIterable, Identifiable {
    case segments, midnight, mono, violet

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .segments: return "Cra"
        case .midnight: return "Midnight"
        case .mono: return "Mono"
        case .violet: return "Violet"
        }
    }

    /// The alternate icon's name for iOS; nil is the app's own icon.
    public var alternateName: String? {
        switch self {
        case .segments: return nil
        case .midnight: return "AppIcon-Midnight"
        case .mono: return "AppIcon-Mono"
        case .violet: return "AppIcon-Violet"
        }
    }

    /// The picture the picker shows.
    public var previewName: String { (alternateName ?? "AppIcon") + "-Preview" }

    public init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .segments
    }
}

/// First launch, in Arc Search's order and (where they fit Cra) its words.
public enum MobileOnboarding {
    public enum Step: String, Equatable {
        case welcome, meet, browseForMe, pinch, icon, blocking, defaultBrowser
    }

    public struct Card: Equatable {
        public var title: String
        public var detail: String
        public var symbol: String
    }

    /// The steps shown. Browse for Me and Pinch to Summarize only for phones whose own model can do them.
    public static func steps(canUseAI: Bool) -> [Step] {
        [.welcome, .meet] + (canUseAI ? [.browseForMe, .pinch] : []) + [.icon, .blocking, .defaultBrowser]
    }

    /// Titles as Arc Search 1.49 sets them (Victor's recording), with the italic words between
    /// asterisks (Markdown, as SwiftUI's Text reads it); `plain(_:)` gives the words alone.
    public static let welcomeTitle = "Get what you want *twice* as fast."
    public static let meetTitle = "Meet your new favorite browser"
    public static let cards = [
        Card(title: "Protect your privacy", detail: "Cra blocks all creepy trackers", symbol: "hand.raised.fill"),
        Card(title: "Auto-archives old tabs", detail: "No more virtual dust bunnies", symbol: "archivebox.fill"),
        Card(title: "Keep your logins", detail: "Passwords carry over from Safari", symbol: "key.fill"),
        Card(title: "Navigate faster", detail: "Swipe anywhere to go back", symbol: "hand.point.up.left.fill"),
    ]
    public static let browseTitle = "Let Cra *search* and *summarize for you*"
    /// What the phone in the Browse for Me step says over its search sheet, arrow to the first chip.
    public static let browseTryIt = "Try it!"
    /// Arc Search's sample queries, in the order of its step (the recording, 0:12).
    public static let sampleQueries = ["things to do in paris", "vegetarian dinner ideas", "who are the beatles", "risotto vs paella",
                                       "romantic shakespearean reply"]
    public static let pinchTitle = "*Pinch* to summarize any web page"
    public static let iconTitle = "Pick an icon for your *home screen*"
    public static let blockingTitle = "Get what you need, without the noise"
    public static let blockingSwitch = "Block Ads and Trackers"
    /// The last step (the recording, 1:06): a pale page, the app's icon, these words, "Set as
    /// Default Browser" and "Skip".
    public static let defaultBrowserTitle = "Never see another ad."
    public static let defaultBrowserBody = "Make sure links from messages and other apps also open in Cra, with adblock, every time."
    public static let defaultBrowserSkip = "Skip"
    /// "Set as Default Browser" brings up an inset sheet with the way there.
    public static let howToTitle = "How to change your default browser"
    public static let howToBody = "Set Cra as your default to automatically open links from other apps."
    public static let defaultBrowserSteps = ["1. Open Cra in Settings", "2. Tap on \u{201C}Default Browser App\u{201D}", "3. Select Cra"]
    public static let howToOpen = "Open Cra in Settings"
    public static let howToLater = "Maybe later"

    /// The words of a title without its emphasis marks.
    public static func plain(_ title: String) -> String { title.replacingOccurrences(of: "*", with: "") }

    /// The button under a step. The Browse for Me and Pinch steps show it only once tried
    /// (until then "Skip" sits at the top right, as in Arc Search's Pinch step).
    public static func buttonTitle(for step: Step) -> String {
        switch step {
        case .blocking: return "Let\u{2019}s go"
        case .defaultBrowser: return "Set as Default Browser"
        default: return "Next"
        }
    }

    public static func showsNext(_ step: Step, tried: Bool) -> Bool {
        switch step {
        case .browseForMe, .pinch: return tried
        default: return true
        }
    }

    public static func showsSkip(_ step: Step, tried: Bool) -> Bool {
        (step == .browseForMe || step == .pinch) && !tried
    }

    /// Arc Search's vivid gradient stays behind every step but the last, which is pale.
    public static func isVivid(_ step: Step) -> Bool { step != .defaultBrowser }
}
