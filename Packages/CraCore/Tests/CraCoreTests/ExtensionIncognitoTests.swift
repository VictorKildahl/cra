import CraCore
import Foundation
import Testing

/// What an incognito window lists: the extensions its profile allows in incognito (GitHub #620).
struct ExtensionIncognitoTests {
    /// "Allow in Incognito" is `incognito: true` in the extension's extensions.settings entry;
    /// missing or false means not allowed.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/620"))
    func allowedIDsReadAllowInIncognito() {
        let settings: [String: Any] = [
            "ublock": ["state": 1, "incognito": true],
            "protonpass": ["state": 1],
            "darkreader": ["state": 1, "incognito": false],
            "numeric": ["state": 1, "incognito": NSNumber(value: 1)],
            "broken": "not a dictionary",
        ]
        #expect(ExtensionIncognito.allowedIDs(settings: settings) == ["ublock", "numeric"])
        #expect(ExtensionIncognito.allowedIDs(settings: [:]).isEmpty)
    }

    /// A normal window lists every turned-on extension; an incognito one only those allowed there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/620"))
    func incognitoListsOnlyAllowed() {
        #expect(ExtensionIncognito.lists(allowedInIncognito: false, incognito: false))
        #expect(ExtensionIncognito.lists(allowedInIncognito: true, incognito: false))
        #expect(ExtensionIncognito.lists(allowedInIncognito: true, incognito: true))
        #expect(!ExtensionIncognito.lists(allowedInIncognito: false, incognito: true))
    }
}
