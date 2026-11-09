import Foundation

/// Words on a page's context menu that Cra changes, taken from Chromium's own strings so they
/// read in the language Chromium runs in, as Arc's do (GitHub #276). Chromium's resource bundle
/// gives them as its .grd files have them: `$1` where a name goes and `&` before a mnemonic,
/// which Chromium's Mac menus leave out when they show the label.
public enum PageMenuLabels {
    /// Chromium 156's Google Lens item, "Search Image with <engine>", as Chrome's own image search
    /// item, "Search <engine> for Image", which Arc shows: Russian «Найти через Google» becomes
    /// «Найти картинку (Google)». Nil when the label isn't the Lens template's: Chromium's item stays.
    public static func imageSearch(lensLabel: String, lensTemplate: String, webTemplate: String) -> String? {
        guard webTemplate.contains("$1"), let engine = argument(in: lensLabel, template: lensTemplate),
              !engine.isEmpty else { return nil }
        return webTemplate.replacingOccurrences(of: "$1", with: engine)
    }

    /// What a template was filled in with at `$1`: "Google" from "Search Image with Google" and
    /// "Search Image with $1". Mnemonics don't count.
    static func argument(in label: String, template: String) -> String? {
        let label = withoutMnemonics(label)
        let parts = withoutMnemonics(template).components(separatedBy: "$1")
        guard parts.count == 2, label.count >= parts[0].count + parts[1].count,
              label.hasPrefix(parts[0]), label.hasSuffix(parts[1]) else { return nil }
        return String(label.dropFirst(parts[0].count).dropLast(parts[1].count))
    }

    /// A label as Chromium's Mac menus show it (l10n_util::FixUpWindowsStyleLabel): a "(&T)"
    /// goes, "&&" is "&", any other "&" goes.
    public static func withoutMnemonics(_ label: String) -> String {
        var out = "", chars = Array(label), i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "(", i + 3 < chars.count, chars[i + 1] == "&", chars[i + 3] == ")" { i += 4; continue }
            if c == "&" {
                if i + 1 < chars.count, chars[i + 1] == "&" { out.append("&"); i += 2 } else { i += 1 }
                continue
            }
            out.append(c)
            i += 1
        }
        return out
    }
}
