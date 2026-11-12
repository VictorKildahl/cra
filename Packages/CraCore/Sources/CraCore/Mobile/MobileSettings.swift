import Foundation

/// What Arc Search's Site Settings sheet switches: the three blockers, then how the page behaves.
/// Each has a value for every site (Global Site Settings) that a single site can override.
public struct MobileSiteOptions: Codable, Equatable {
    public var blockAds = true
    public var blockCookieBanners = true
    public var blockTrackers = true
    public var pinchToSummarize = true
    public var collapseBottomBar = true
    public var swipeToNavigate: MobileSwipeToNavigate = .fromAnywhere

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case blockAds, blockCookieBanners, blockTrackers, pinchToSummarize, collapseBottomBar, swipeToNavigate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockAds = try c.decodeIfPresent(Bool.self, forKey: .blockAds) ?? true
        blockCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .blockCookieBanners) ?? true
        blockTrackers = try c.decodeIfPresent(Bool.self, forKey: .blockTrackers) ?? true
        pinchToSummarize = try c.decodeIfPresent(Bool.self, forKey: .pinchToSummarize) ?? true
        collapseBottomBar = try c.decodeIfPresent(Bool.self, forKey: .collapseBottomBar) ?? true
        swipeToNavigate = (try? c.decodeIfPresent(MobileSwipeToNavigate.self, forKey: .swipeToNavigate)) ?? .fromAnywhere
    }
}

/// Where a sideways swipe goes back and forward: anywhere on the page, or only from its edges.
public enum MobileSwipeToNavigate: String, Codable, CaseIterable, Identifiable {
    case fromAnywhere, fromEdges

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fromAnywhere: return "From Anywhere"
        case .fromEdges: return "From Edges"
        }
    }
}

/// One site's own choices: only what differs from the global options is kept.
public struct MobileSiteOverride: Codable, Equatable {
    public var blockAds: Bool?
    public var blockCookieBanners: Bool?
    public var blockTrackers: Bool?
    public var pinchToSummarize: Bool?
    public var collapseBottomBar: Bool?
    public var swipeToNavigate: MobileSwipeToNavigate?

    public init() {}

    var isEmpty: Bool { self == MobileSiteOverride() }

    func applied(to global: MobileSiteOptions) -> MobileSiteOptions {
        var options = global
        options.blockAds = blockAds ?? global.blockAds
        options.blockCookieBanners = blockCookieBanners ?? global.blockCookieBanners
        options.blockTrackers = blockTrackers ?? global.blockTrackers
        options.pinchToSummarize = pinchToSummarize ?? global.pinchToSummarize
        options.collapseBottomBar = collapseBottomBar ?? global.collapseBottomBar
        options.swipeToNavigate = swipeToNavigate ?? global.swipeToNavigate
        return options
    }

    /// The override that turns `global` into `options`.
    init(_ options: MobileSiteOptions, over global: MobileSiteOptions) {
        blockAds = options.blockAds == global.blockAds ? nil : options.blockAds
        blockCookieBanners = options.blockCookieBanners == global.blockCookieBanners ? nil : options.blockCookieBanners
        blockTrackers = options.blockTrackers == global.blockTrackers ? nil : options.blockTrackers
        pinchToSummarize = options.pinchToSummarize == global.pinchToSummarize ? nil : options.pinchToSummarize
        collapseBottomBar = options.collapseBottomBar == global.collapseBottomBar ? nil : options.collapseBottomBar
        swipeToNavigate = options.swipeToNavigate == global.swipeToNavigate ? nil : options.swipeToNavigate
    }
}

/// Where a tapped link to a site with an installed app goes: Arc Search's "Open App Links in...".
public enum MobileAppLinks: String, Codable, CaseIterable, Identifiable {
    case browser, nativeApp

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .browser: return "Cra"
        case .nativeApp: return "Native App"
        }
    }
}

extension MobileAppLinks {
    /// Whether a navigation is first offered to an installed app (iOS opens it only when an app
    /// claims the address as a universal link, else the page loads here). Only a link tapped in the
    /// page itself, to an http(s) address on another site: a typed address, a reload, a redirect or a
    /// link within the same site stays in the browser, so a site can't bounce the user into its app.
    public func offersApp(isLinkTap: Bool, isMainFrame: Bool, from current: String?, to target: String) -> Bool {
        guard self == .nativeApp, isLinkTap, isMainFrame, let url = URL(string: target),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host.map(MobileSettings.siteKey), !host.isEmpty else { return false }
        guard let current = current.flatMap({ URL(string: $0)?.host }).map(MobileSettings.siteKey), !current.isEmpty else { return true }
        let sameSite = host == current || host.hasSuffix("." + current) || current.hasSuffix("." + host)
        return !sameSite
    }
}

/// `settings.json` in the iPhone app's data folder. Every field has a default, so a file from an
/// older build loads and a missing file is the defaults.
public struct MobileSettings: Codable, Equatable {
    public var searchEngine: MobileSearchEngine = .google
    public var archiveAfter: MobileArchiveAfter = .oneDay
    /// Arc Search comes up ready to type.
    public var opensKeyboardOnLaunch = true
    public var openAppLinksIn: MobileAppLinks = .nativeApp
    /// Global Site Settings.
    public var siteDefaults = MobileSiteOptions()
    /// Sites that differ, keyed by `siteKey`.
    public var siteOverrides: [String: MobileSiteOverride] = [:]
    public var hasSeenOnboarding = false
    /// "Browse for Me" picked as the search engine: a search makes a Browse for Me page, while
    /// `searchEngine` still gives the suggestions and takes the search when no answer comes.
    public var searchesWithBrowseForMe = false
    /// App Settings ▸ Languages: what Browse for Me, summaries and Translate answer in, as a
    /// language code; nil follows the iPhone's language.
    public var answerLanguage: String?

    public init() {}

    /// The Search Engine row's value.
    public var searchChoice: MobileSearchChoice {
        get { searchesWithBrowseForMe ? .browseForMe : .engine(searchEngine) }
        set {
            switch newValue {
            case .browseForMe: searchesWithBrowseForMe = true
            case .engine(let engine): searchesWithBrowseForMe = false; searchEngine = engine
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case searchEngine, archiveAfter, opensKeyboardOnLaunch, openAppLinksIn, siteDefaults, siteOverrides, hasSeenOnboarding, searchesWithBrowseForMe, answerLanguage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = (try? c.decodeIfPresent(MobileSearchEngine.self, forKey: .searchEngine)) ?? .google
        archiveAfter = (try? c.decodeIfPresent(MobileArchiveAfter.self, forKey: .archiveAfter)) ?? .oneDay
        opensKeyboardOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .opensKeyboardOnLaunch) ?? true
        openAppLinksIn = (try? c.decodeIfPresent(MobileAppLinks.self, forKey: .openAppLinksIn)) ?? .nativeApp
        siteDefaults = try c.decodeIfPresent(MobileSiteOptions.self, forKey: .siteDefaults) ?? MobileSiteOptions()
        siteOverrides = try c.decodeIfPresent([String: MobileSiteOverride].self, forKey: .siteOverrides) ?? [:]
        hasSeenOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        searchesWithBrowseForMe = try c.decodeIfPresent(Bool.self, forKey: .searchesWithBrowseForMe) ?? false
        answerLanguage = (try? c.decodeIfPresent(String.self, forKey: .answerLanguage)).flatMap { MobileLanguages.codes.contains($0) ? $0 : nil }
    }

    /// What applies on `host`: the site's own choices over the global ones.
    public func options(for host: String?) -> MobileSiteOptions {
        guard let host, let site = siteOverrides[Self.siteKey(host)] else { return siteDefaults }
        return site.applied(to: siteDefaults)
    }

    /// Records a site's choices, and forgets the site once it matches the global options again.
    public mutating func setOptions(_ options: MobileSiteOptions, for host: String) {
        let override = MobileSiteOverride(options, over: siteDefaults)
        siteOverrides[Self.siteKey(host)] = override.isEmpty ? nil : override
    }

    /// A site is its host without `www.`, lowercased.
    public static func siteKey(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}

/// The languages answers can be written in: those Apple Intelligence's on-device model writes
/// (Arc Search's own list was not seen).
public enum MobileLanguages {
    public static let codes = ["en", "da", "de", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr", "vi", "zh"]

    /// The language answers are written in: the setting, else the first of the iPhone's
    /// languages that the model writes, else English.
    public static func answerCode(setting: String?, preferred: [String]) -> String {
        if let setting, codes.contains(setting) { return setting }
        for identifier in preferred {
            let code = String(identifier.prefix { $0 != "-" && $0 != "_" }).lowercased()
            let normalized = code == "no" || code == "nn" ? "nb" : code
            if codes.contains(normalized) { return normalized }
        }
        return "en"
    }

    /// The language's name in English, for the model's instructions ("Danish").
    public static func englishName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
