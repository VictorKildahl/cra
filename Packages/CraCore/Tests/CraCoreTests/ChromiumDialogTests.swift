import CoreGraphics
import CraCore
import Testing

struct ChromiumDialogTests {
    static let titled: UInt = 1 << 0, closable: UInt = 1 << 1, miniaturizable: UInt = 1 << 2, resizable: UInt = 1 << 3
    static let fullSizeContentView: UInt = 1 << 15

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func theInstallPromptIsOne() {
        // What Chromium 156 made the "Add “Google Translate”?" prompt in Cra 0.1.39 (11 Nov 2026).
        #expect(ChromiumDialog.isParentless(className: "NativeWidgetMacNSWindow", styleMask: Self.titled | Self.fullSizeContentView,
                                            isSheet: false, hasParent: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"), arguments: [
        // A Chromium browser window (a page's, the Task Manager): Chromium's TYPE_WINDOW style.
        ("NativeWidgetMacNSWindow", titled | closable | miniaturizable | resizable, false, false),
        // A bubble or an extension's popup: borderless.
        ("NativeWidgetMacNSWindow", 0, false, false),
        // Shown as a sheet, as in Chrome, or already over a Cra window.
        ("NativeWidgetMacNSWindow", titled | fullSizeContentView, true, false),
        ("NativeWidgetMacNSWindow", titled | fullSizeContentView, false, true),
        // Cra's own windows are never Chromium's.
        ("Cra.DialogPanel", titled | fullSizeContentView, false, false),
    ])
    func othersAreNot(className: String, styleMask: UInt, isSheet: Bool, hasParent: Bool) {
        #expect(!ChromiumDialog.isParentless(className: className, styleMask: styleMask, isSheet: isSheet, hasParent: hasParent))
    }

    /// The MacBook's screen (1728 × 1117 pt, menu bar 33 pt) and the window of the report.
    static let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    static let window = CGRect(x: 164, y: 153, width: 1400, height: 880)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func hangsWhereASheetDoes() {
        // Chromium had centred the 448 × 196 pt prompt too, but 139 pt lower, in the page.
        let f = ChromiumDialog.frame(size: CGSize(width: 448, height: 196), over: Self.window, titleBarHeight: 32, screen: Self.screen)
        #expect(f == CGRect(x: 640, y: 805, width: 448, height: 196))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func staysOnTheScreen() {
        // A window half off the screen's left edge: the dialog comes back onto it.
        let left = CGRect(x: -900, y: 153, width: 1400, height: 880)
        #expect(ChromiumDialog.frame(size: CGSize(width: 448, height: 132), over: left, titleBarHeight: 32, screen: Self.screen).minX == 0)
        // One whose top is above the screen's: the dialog's top is the screen's.
        let high = CGRect(x: 164, y: 600, width: 1400, height: 880)
        #expect(ChromiumDialog.frame(size: CGSize(width: 448, height: 196), over: high, titleBarHeight: 32, screen: Self.screen).maxY == 1084)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/349"))
    func tallerThanTheScreenKeepsItsTitle() {
        let f = ChromiumDialog.frame(size: CGSize(width: 448, height: 1300), over: Self.window, titleBarHeight: 32, screen: Self.screen)
        #expect(f.maxY == Self.screen.maxY)
    }
}
