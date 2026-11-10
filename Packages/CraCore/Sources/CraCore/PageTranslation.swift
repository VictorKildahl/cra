import Foundation

/// A page's translation as Chromium keeps it, for Arc's translate UI (GitHub #310): the
/// button in the toolbar, the affordance under the sidebar's URL field, the popover they open
/// and the toasts. Chromium detects the language and translates; Cra draws the UI that Arc
/// draws instead of Chrome's bubble (scripts/cef-patches/translate-ui.patch).
///
/// The state arrives as JSON: pushed as "Cra.translate" whenever it changes (with `step` when
/// Chromium would have shown its bubble), and as the reply to every Cra.*Translate* method
/// (Cra.getTranslateState adds `languages`).
public struct PageTranslation: Equatable, Sendable {
    /// The step Chromium's bubble would have shown (translate::TranslateStep).
    public enum Step: String, Equatable, Sendable {
        /// Chromium offers to translate the page (it would have opened its bubble by itself).
        case offer
        case translating
        case translated
        case reverted
        case error
    }

    /// The page the state is for: a state for another address is stale.
    public var url = ""
    /// The page's language as Chromium detected it ("ru", "zh-CN"; "und" when it can't tell).
    public var source = ""
    /// The language the page shows now: the source, or the one it was translated to.
    public var current = ""
    /// The language Chromium would translate to (the first of the profile's languages it supports).
    public var target = ""
    /// Chromium could translate the page (its omnibox icon would show).
    public var available = false
    public var translated = false
    /// A translation is under way.
    public var pending = false
    /// The site is on the profile's never-translate list.
    public var neverSite = false
    public var step: Step?
    /// translate::TranslateErrors, 0 for none.
    public var error = 0
    /// The step comes from something the user did (Cra's popover, the page's context menu).
    public var userGesture = false
    /// The languages Chromium can translate to; only Cra.getTranslateState sends them.
    public var languages: [String] = []

    public init(url: String = "", source: String = "", current: String = "", target: String = "",
                available: Bool = false, translated: Bool = false, pending: Bool = false, neverSite: Bool = false,
                step: Step? = nil, error: Int = 0, userGesture: Bool = false, languages: [String] = []) {
        self.url = url
        self.source = source
        self.current = current
        self.target = target
        self.available = available
        self.translated = translated
        self.pending = pending
        self.neverSite = neverSite
        self.step = step
        self.error = error
        self.userGesture = userGesture
        self.languages = languages
    }

    /// Nil for anything that isn't a state object (an empty `{}` too: a page with no translate client).
    public init?(json: String) {
        guard let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["url"] != nil else { return nil }
        url = o["url"] as? String ?? ""
        source = o["source"] as? String ?? ""
        current = o["current"] as? String ?? ""
        target = o["target"] as? String ?? ""
        available = o["available"] as? Bool ?? false
        translated = o["translated"] as? Bool ?? false
        pending = o["pending"] as? Bool ?? false
        neverSite = o["neverSite"] as? Bool ?? false
        step = (o["step"] as? String).flatMap(Step.init(rawValue:))
        error = o["error"] as? Int ?? 0
        userGesture = o["userGesture"] as? Bool ?? false
        languages = (o["languages"] as? [String]) ?? []
    }

    /// Whether the page has the translate button (the toolbar's, or the sidebar's affordance):
    /// Chromium could translate it, or it is translated or being translated, so it can go back.
    /// Chromium sends its offer just before it marks the page translatable, so an offer counts.
    /// A site on the never-translate list has none, as in Arc (its `translateNeverHosts`).
    public var offersTranslation: Bool { (available || step == .offer) && !neverSite || translated || pending }

    /// The language the popover's Translate button translates to.
    public var translateTarget: String { target.isEmpty ? "en" : target }

    /// The popover's line (Arc: "Prompt string for a translate offer" / "…for a translated page").
    public var prompt: String {
        translated
            ? "Translated from \(Self.name(of: source))."
            : "Translate this page to \(Self.name(of: translateTarget))?"
    }

    /// Arc's toast for a step Chromium reached, if it gets one: done or failed.
    public var toast: String? {
        switch step {
        case .translated: return translated ? "Translated to \(Self.name(of: current))" : nil
        case .error: return "Translation error (\(Self.errorName(error)))"
        default: return nil
        }
    }

    /// Arc's toast after Show Original.
    public var revertedToast: String { "Translated back to \(Self.name(of: source))" }

    /// "Choose Another Language": every language Chromium translates to but the one shown now,
    /// by name.
    public var otherLanguages: [String] {
        languages.filter { $0 != current && $0 != "und" }
            .sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
    }

    /// A language's name in Cra's English UI, as Chrome's translate bubble names it.
    public static func name(of code: String) -> String {
        switch code {
        case "", "und": return "Unknown"
        case "zh-CN": return "Chinese (Simplified)"
        case "zh-TW": return "Chinese (Traditional)"
        // Chromium's codes for languages ICU knows by newer ones.
        case "iw": return name(of: "he")
        case "jw": return name(of: "jv")
        case "tl": return name(of: "fil")
        default: break
        }
        let english = Locale(identifier: "en_US")
        return english.localizedString(forIdentifier: code)
            ?? english.localizedString(forLanguageCode: code)
            ?? code
    }

    /// translate::TranslateErrors in words.
    public static func errorName(_ code: Int) -> String {
        switch code {
        case 1: return "network"
        case 2: return "initialization"
        case 3: return "unknown language"
        case 4: return "unsupported language"
        case 5: return "identical languages"
        case 6: return "translation"
        case 7: return "timeout"
        case 8: return "script"
        case 9: return "bad origin"
        case 10: return "script load"
        default: return "unknown"
        }
    }
}
