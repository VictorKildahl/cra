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

    public static let welcomeTitle = "Get what you want twice as fast."
    public static let meetTitle = "Meet your new favorite browser"
    public static let cards = [
        Card(title: "Protect your privacy", detail: "Cra blocks all creepy trackers", symbol: "hand.raised.fill"),
        Card(title: "Auto-archives old tabs", detail: "No more virtual dust bunnies", symbol: "archivebox.fill"),
        Card(title: "Keep your logins", detail: "Passwords carry over from Safari", symbol: "key.fill"),
        Card(title: "Navigate faster", detail: "Swipe anywhere to go back", symbol: "hand.draw.fill"),
    ]
    public static let browseTitle = "Let Cra search and summarize for you"
    /// Arc Search's sample queries.
    public static let sampleQueries = ["things to do in paris", "who are the beatles", "romantic shakespearean reply", "risotto vs paella",
                                       "vegetarian dinner ideas"]
    /// Arc Search's step 5 ("Pinch" in italics), from 60fps.design's clip of it.
    public static let pinchTitle = "Pinch to summarize any web page"
    public static let iconTitle = "Pick an icon for your home screen"
    public static let blockingTitle = "Get what you need, without the noise"
    public static let blockingSwitch = "Block Ads and Trackers"
    /// The default-browser step in Arc Search's words (its launch build, 60fps.design's clip; the
    /// late-2024 build's wording was not seen): the three steps in Settings, "Open Settings", "Not now".
    public static let defaultBrowserTitle = "Switch Your Default Browser"
    public static let defaultBrowserSteps = ["Go to Settings", "Tap Default Browser App", "Select Cra"]
    public static let defaultBrowserSkip = "Not now"

    /// The button under a step: "Next" until the blocking step's "Let’s go".
    public static func buttonTitle(for step: Step) -> String {
        switch step {
        case .blocking: return "Let’s go"
        case .defaultBrowser: return "Open Settings"
        default: return "Next"
        }
    }
}
