import Foundation

/// A tab restored at launch can ask for an extension's page (its options page, say) before
/// Chromium has loaded the extension: `--load-extension` loads the `Extensions` folder after the
/// restored tabs start loading (the same race ForceWebRequestProxyForTest covers for webRequest).
/// Chromium then blocks the page with ERR_BLOCKED_BY_CLIENT and shows its error page until a
/// reload. Arc and Chrome install their extensions before restoring tabs, so the page just loads.
/// Cra loads it again a few times while the extension comes up. An extension that is off or gone
/// in the tab's profile is not retried: its error page is the answer.
public enum ExtensionPageRetry {
    /// net::ERR_BLOCKED_BY_CLIENT.
    public static let blockedByClient = -20
    /// 0.25, 0.5, 1, 2, 4, 4 s: about 12 s in all.
    public static let attempts = 6

    /// The extension ID of a `chrome-extension://<id>/…` address.
    public static func extensionID(of url: String) -> String? {
        guard let u = URLComponents(string: url), u.scheme == "chrome-extension", let id = u.host, !id.isEmpty else { return nil }
        return id
    }

    /// How long to wait before loading `url` again after it failed with `errorCode` for the
    /// `attempt`-th time (0 first), or nil to leave the error. `isOn` says whether the
    /// extension is installed and turned on in the tab's profile.
    public static func delay(url: String, errorCode: Int, attempt: Int, isOn: (String) -> Bool) -> TimeInterval? {
        guard errorCode == blockedByClient, attempt >= 0, attempt < attempts,
              let id = extensionID(of: url), isOn(id) else { return nil }
        return min(0.25 * pow(2, Double(attempt)), 4)
    }
}
