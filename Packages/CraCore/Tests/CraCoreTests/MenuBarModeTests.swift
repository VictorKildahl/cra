import CraCore
import Foundation
import Testing

/// "Keep Cra in the menu bar" (GitHub #231): ⌘Q stays in the menu bar; everything else quits.
struct MenuBarModeTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231")) func onlyCrasOwnQuitStaysInTheMenuBar() {
        #expect(MenuBarMode.outcome(enabled: true, source: .appMenu) == .stayInMenuBar)
        for source: MenuBarMode.QuitSource in [.menuBarItem, .appleEvent, .relaunch] {
            #expect(MenuBarMode.outcome(enabled: true, source: source) == .quit)
        }
    }

    /// Off (the default), ⌘Q quits as in Arc.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231")) func offEveryQuitQuits() {
        for source: MenuBarMode.QuitSource in [.appMenu, .menuBarItem, .appleEvent, .relaunch] {
            #expect(MenuBarMode.outcome(enabled: false, source: source) == .quit)
        }
        #expect(AppSettings().keepInMenuBar == false)
        let old = try! JSONDecoder().decode(AppSettings.self, from: Data(#"{"warnBeforeQuitting": true}"#.utf8))
        #expect(old.keepInMenuBar == false)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231")) func theDockIconGoesOnlyWhileNothingIsOpen() {
        #expect(MenuBarMode.showsInDock(inMenuBar: false, windowsOpen: false))
        #expect(MenuBarMode.showsInDock(inMenuBar: false, windowsOpen: true))
        #expect(MenuBarMode.showsInDock(inMenuBar: true, windowsOpen: true))
        #expect(!MenuBarMode.showsInDock(inMenuBar: true, windowsOpen: false))
    }

    /// The windows a relaunch would bring back are put away; incognito ones close like on a quit.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231")) func incognitoWindowsCloseTheRestArePutAway() {
        let normal = UUID(), blank = UUID(), incognito = UUID(), second = UUID()
        let windows: [MenuBarMode.Window] = [.init(id: normal, kind: .normal), .init(id: incognito, kind: .incognito),
                                             .init(id: blank, kind: .blank), .init(id: second, kind: .normal)]
        let all = MenuBarMode.windowsOnQuit(windows, active: incognito, restoreWindows: true)
        #expect(all.keep == [normal, blank, second])
        #expect(all.close == [incognito])
    }

    /// "Restore windows from previous session" off: one window comes back, as after a relaunch.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/231")) func withoutRestoringWindowsOnlyTheOneInUseIsKept() {
        let normal = UUID(), blank = UUID(), incognito = UUID(), second = UUID()
        let windows: [MenuBarMode.Window] = [.init(id: normal, kind: .normal), .init(id: incognito, kind: .incognito),
                                             .init(id: blank, kind: .blank), .init(id: second, kind: .normal)]
        let active = MenuBarMode.windowsOnQuit(windows, active: second, restoreWindows: false)
        #expect(active.keep == [second])
        #expect(active.close == [normal, incognito, blank])
        // A Blank or incognito window in use: a normal one is kept instead.
        #expect(MenuBarMode.windowsOnQuit(windows, active: blank, restoreWindows: false).keep == [normal])
        #expect(MenuBarMode.windowsOnQuit(windows, active: incognito, restoreWindows: false).keep == [normal])
        #expect(MenuBarMode.windowsOnQuit([.init(id: blank, kind: .blank)], active: blank, restoreWindows: false).keep == [blank])
    }
}
