import Foundation

/// The iPhone app's icons: the Mac app's, in its order (Settings ▸ Icon, AppIconManager.presets): Segments, Arc's
/// own icon set redrawn around Cra's C by Provok (brand/arc-icons), then Cra's earlier alternates.
public enum MobileAppIcon: String, CaseIterable, Identifiable {
    // Cra's own four first: the sheet is one row that scrolls sideways, and the icons onboarding offered stay in
    // reach without scrolling. Arc's set follows in the Mac's order.
    case segments, midnight, mono, violet
    case original, candy, hologram, neon
    case flutedGlass = "fluted-glass"
    case schoolbook, colorful, canary
    case earlyBirds = "early-birds"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .segments: return "Cra"
        case .flutedGlass: return "Fluted Glass"
        case .earlyBirds: return "Early Birds"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// The alternate icon's name for iOS (its set in the asset catalog, `AppIcon-<Label>`); nil is the app's own icon.
    public var alternateName: String? {
        self == .segments ? nil : "AppIcon-" + label.replacingOccurrences(of: " ", with: "")
    }

    /// The picture the picker shows.
    public var previewName: String { (alternateName ?? "AppIcon") + "-Preview" }

    /// Onboarding's icon step keeps Arc Search's two-by-two grid: Cra's own four. Settings ▸ App Icon and the
    /// App Icon sheet offer every icon.
    public static let onboardingChoices: [MobileAppIcon] = [.segments, .midnight, .mono, .violet]

    public init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .segments
    }
}

/// First launch, in Arc Search's order and (where they fit Cra) its words.
public enum MobileOnboarding {
    public struct Mock: Equatable {
        public enum Shape: String { case phone, duoClosed, duoOpen }
        public let shape: Shape
        public let size: CGSize
        public let logicalSize: CGSize
        public let columnWidth: CGFloat
        public let keyWidth: CGFloat
        public let keyHeight: CGFloat
    }

    /// Phones are longer than 1.6 in either orientation; iPads are shorter but have no side inset.
    /// The folding screen is both short and one-sided.
    public static func mock(window: CGSize, safeLeft: CGFloat, safeRight: CGFloat) -> Mock {
        guard max(window.width, window.height) / min(window.width, window.height) < 1.6,
              (safeLeft > 0) != (safeRight > 0) else {
            return Mock(shape: .phone, size: CGSize(width: 330, height: 640),
                        logicalSize: CGSize(width: 330, height: 640), columnWidth: 330, keyWidth: 26, keyHeight: 30)
        }
        let closed = window.height > window.width
        let size = closed ? CGSize(width: 330, height: 330 * window.height / window.width)
                          : CGSize(width: 450 * window.width / window.height, height: 450)
        // The existing mock draws Apple's 393 pt phone at 330 pt.
        let logicalSize = CGSize(width: window.width * 330 / 393, height: window.height * 330 / 393)
        let columnWidth = closed ? logicalSize.width : min(logicalSize.width, 540) // SheetHost's wide content cap.
        // Research's open keyboard: the first row spans 82% of the screen, with nine 4 pt gaps.
        let keyWidth = closed ? (logicalSize.width - 52) / 10 : (0.82 * logicalSize.width - 36) / 10
        return Mock(shape: closed ? .duoClosed : .duoOpen, size: size, logicalSize: logicalSize,
                    columnWidth: columnWidth, keyWidth: keyWidth, keyHeight: closed ? 30 : 36)
    }

    /// Keeps the exact iPhone layout while its small overflow stays on screen;
    /// otherwise shrinks only the step's picture to fit the available height.
    public static func fitScale(available: CGFloat, topInset: CGFloat, bottomInset: CGFloat, heading: CGFloat,
                                scalable: CGFloat, topPadding: CGFloat = 40, spacing: CGFloat = 24,
                                bottomReserved: CGFloat = 0) -> CGFloat {
        let available = available - bottomReserved
        let fixed = topPadding + heading + spacing
        let allowance = bottomReserved > 0 ? 0 : min(topPadding + topInset, bottomInset)
        if fixed + scalable - available <= 2 * allowance { return 1 }
        return min(1, max(0, (available - fixed) / scalable))
    }

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
