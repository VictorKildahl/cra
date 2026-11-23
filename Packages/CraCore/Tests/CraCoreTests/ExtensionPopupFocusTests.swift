import CraCore
import Testing

/// An extension popup stays open while its DevTools take focus (GitHub #701).
struct ExtensionPopupFocusTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/701"))
    func chromiumsDevToolsWindowKeepsThePopup() {
        #expect(ExtensionPopupFocus.isDevTools(title: "DevTools - chrome-extension://aeblfdkhhhdcdjpifhhbdiojplfjncoa/popup.html"))
        #expect(ExtensionPopupFocus.isDevTools(title: "DevTools"))
        #expect(!ExtensionPopupFocus.isDevTools(title: "Cra"))
        #expect(!ExtensionPopupFocus.isDevTools(title: "DevToolsHelper"))
        #expect(!ExtensionPopupFocus.isDevTools(title: ""))
    }
}
