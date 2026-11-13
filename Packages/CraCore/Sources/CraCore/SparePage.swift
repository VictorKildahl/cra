import Foundation

/// Making a Chromium page costs the main thread ~34 ms on average and up to ~100 ms (CEF makes a
/// whole macOS window per page: measured 12 Nov 2026 on a real sidebar, docs/speed.md), paid by a
/// new tab, a link opened in a tab and the first visit to a restored tab. Cra keeps one page per
/// profile made ahead, when nothing waits on it, and the next tab that needs a page takes it.
public enum SparePage {
    /// How long after a page was made or taken the next spare is made: past the click that took
    /// it, so making it never lands on the same frame.
    public static let refillDelay: TimeInterval = 1

    /// Which tabs can take a spare: a Chromium page in a normal profile. A DRM service opens in
    /// WebKit, an easel is Cra's own canvas, and an incognito page belongs to no profile's spare.
    public static func canTake(engine: PageEngine, isEasel: Bool, incognito: Bool) -> Bool {
        engine == .chromium && !isEasel && !incognito
    }

    /// The key a profile's spare is kept under (nil is the Default profile).
    public static func key(profilePath: String?) -> String { profilePath ?? "" }
}
