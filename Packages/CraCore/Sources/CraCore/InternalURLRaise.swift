import Foundation

/// Whether a `cra://` URL (from another app, a shell's `open`, the command file) brings the
/// browser window and Cra to the front before it runs.
public enum InternalURLRaise {
    /// `host`: the URL's host (`open`, `action`, `commandbar`…). `little`, `background`: `open`'s
    /// `little=1` and `background=1`. `littleWindowIsKey`: a Little Window has the keyboard.
    public static func raises(host: String?, little: Bool, background: Bool, littleWindowIsKey: Bool) -> Bool {
        switch host {
        // An action goes to the key Little Window when there is one, and that stays in front.
        case "action": return !littleWindowIsKey
        // A Little Window opens on the Space in use, over the app in use, by itself (#186).
        // background=1 adds the tab without switching to it: Cra stays behind the app in use.
        case "open": return !little && !background
        default: return true
        }
    }
}
