import Foundation

/// Chromium's application locale (`CefSettings.locale`, `--lang`), picked the way Chrome and
/// Arc pick it on macOS: the first macOS language the browser has a translation for, matched by
/// macOS itself (Chrome's `OverrideLocaleWithCocoaLocale` reads its bundle's
/// `preferredLocalizations`, and Arc's bundle carries one `.lproj` per Chromium locale).
///
/// It decides which voice speaks an utterance that has no `lang` (#167), what language
/// Chromium's own pages, dialogs and menus are in, how pages format dates by default, and a new
/// profile's Accept-Language. Without it CEF forces en-US whatever macOS is set to.
public enum ChromiumLocale {
    /// `available` is the framework's localization folder names ("en", "en_GB", "zh_CN",
    /// "af_FEMININE"), `preferredLanguages` the user's macOS languages, most wanted first
    /// ("zh-Hans-CN"). Nil when the framework lists no locales, which leaves CEF's en-US.
    public static func pick(available: [String], preferredLanguages: [String]) -> String? {
        // Chromium 156 ships gendered variants of each locale; they aren't separate languages.
        let candidates = available
            .filter { !["_FEMININE", "_MASCULINE", "_NEUTER"].contains(where: $0.hasSuffix) && $0 != "Base" }
            .map { $0.replacingOccurrences(of: "_", with: "-") }
        guard !candidates.isEmpty else { return nil }
        guard let match = Bundle.preferredLocalizations(from: candidates, forPreferences: preferredLanguages).first else { return nil }
        // On disk Chromium's en-US is just "en" (crbug.com/25578); Chrome maps it back.
        return match == "en" ? "en-US" : match
    }
}
