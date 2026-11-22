import Foundation

/// Which extensions an incognito window offers (GitHub #620). Chrome's toolbar and extensions menu
/// in an off-the-record profile show only the extensions allowed there (ToolbarActionsModel →
/// extensions::util::IsIncognitoEnabled): chrome://extensions ▸ "Allow in Incognito", kept as
/// `incognito: true` in the extension's `extensions.settings` entry. The others can't see or touch
/// an incognito page, so listing them offers buttons that do nothing.
public enum ExtensionIncognito {
    /// The extension IDs a profile allows in incognito. `settings` is its `extensions.settings`.
    public static func allowedIDs(settings: [String: Any]) -> Set<String> {
        Set(settings.compactMap { id, value in
            guard let s = value as? [String: Any], isTrue(s["incognito"]) else { return nil }
            return id
        })
    }

    /// Whether a window lists an extension that is turned on in its profile: an incognito one only
    /// when the profile allows it in incognito.
    public static func lists(allowedInIncognito: Bool, incognito: Bool) -> Bool { !incognito || allowedInIncognito }

    private static func isTrue(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        return (value as? NSNumber)?.boolValue ?? false
    }
}
