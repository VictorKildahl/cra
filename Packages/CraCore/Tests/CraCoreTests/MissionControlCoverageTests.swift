import CoreGraphics
import CraCore
import Foundation
import Testing

/// A full-screen video went to Picture in Picture each time Mission Control opened, and back to full screen when
/// it closed (#698): macOS calls the window not visible and not on screen while it sits in the Mission Control grid.
/// The Dock's own windows tell Mission Control (and App Exposé) apart from the window really going out of sight.
/// The window lists are the ones the window server gave on macOS 27 (23 Nov 2026), on a 1728 × 1117 display.
@Suite struct MissionControlCoverageTests {
    static let dock: Int32 = 640, cra: Int32 = 54281
    static let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    static func window(_ number: Int, pid: Int32, owner: String, layer: Int, _ r: CGRect, name: String? = nil) -> [String: Any] {
        var d: [String: Any] = [
            "kCGWindowNumber": NSNumber(value: number), "kCGWindowOwnerPID": NSNumber(value: pid),
            "kCGWindowOwnerName": owner, "kCGWindowLayer": NSNumber(value: layer), "kCGWindowAlpha": NSNumber(value: 1),
            "kCGWindowIsOnscreen": true,
            "kCGWindowBounds": ["X": NSNumber(value: Double(r.minX)), "Y": NSNumber(value: Double(r.minY)),
                                "Width": NSNumber(value: Double(r.width)), "Height": NSNumber(value: Double(r.height))],
        ]
        if let name { d["kCGWindowName"] = name }
        return d
    }

    static let menuBar = window(30, pid: 400, owner: "Window Server", layer: 24, CGRect(x: 0, y: 0, width: 1728, height: 33), name: "Menubar")
    static let wallpaper = window(31, pid: dock, owner: "Dock", layer: Int(Int32.min) + 24, display, name: "Wallpaper-")
    /// The Dock's own window when it doesn't hide: the whole display, clear apart from the Dock (#533).
    static let dockBar = window(32, pid: dock, owner: "Dock", layer: 20, display, name: "Dock")
    static let craWindow = window(87008, pid: cra, owner: "Cra", layer: 0, CGRect(x: 0, y: 33, width: 1728, height: 1084))

    /// What the window server lists while Mission Control is up.
    static let missionControl: [[String: Any]] = [
        menuBar,
        window(901, pid: dock, owner: "Dock", layer: 20, CGRect(x: 829, y: 362, width: 132, height: 86)),
        dockBar,
        window(902, pid: dock, owner: "Dock", layer: 18, display),
        window(903, pid: dock, owner: "Dock", layer: 0, display),
        wallpaper,
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/698"))
    func missionControlIsUp() {
        #expect(WindowCoverage.missionControlShowing(Self.missionControl))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/698"))
    func anOrdinaryDesktopIsNotMissionControl() {
        #expect(!WindowCoverage.missionControlShowing([Self.menuBar, Self.craWindow, Self.wallpaper]))
        // The Dock showing, a stack or a tooltip of it: its windows at layer 20.
        #expect(!WindowCoverage.missionControlShowing([Self.menuBar, Self.dockBar, Self.craWindow, Self.wallpaper,
                                                       Self.window(904, pid: Self.dock, owner: "Dock", layer: 20, CGRect(x: 600, y: 700, width: 300, height: 360))]))
        // Another app's window at layer 18 is not the Dock's.
        #expect(!WindowCoverage.missionControlShowing([Self.window(905, pid: 77, owner: "Overlay", layer: 18, Self.display), Self.wallpaper]))
        // A small Dock window at layer 18 doesn't cover a display.
        #expect(!WindowCoverage.missionControlShowing([Self.window(906, pid: Self.dock, owner: "Dock", layer: 18, CGRect(x: 10, y: 10, width: 120, height: 80))]))
        #expect(!WindowCoverage.missionControlShowing([]))
    }

    /// macOS calls the window not visible before Mission Control's windows are listed: the first asks see no
    /// Mission Control, and the video must not leave before they do.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/698"))
    func missionControlComingUpLateStillHoldsTheVideo() {
        var wait = WindowCoverage.OffScreenWait()
        #expect(wait.tick(missionControl: false) == .wait)
        #expect(wait.tick(missionControl: true) == .missionControl)
        for _ in 0..<40 { #expect(wait.tick(missionControl: true) == .wait) }
        #expect(wait.sawMissionControl)
        // Closed on another desktop or window, and the window still off screen: out of sight then.
        #expect(wait.tick(missionControl: false) == .wait)
        #expect(wait.tick(missionControl: false) == .outOfSight)
    }

    /// Another desktop or the Dock, no Mission Control: out of sight after the settle time.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/698"))
    func anotherDesktopIsOutOfSightAfterTheSettleTime() {
        var wait = WindowCoverage.OffScreenWait()
        #expect(wait.tick(missionControl: false) == .wait)
        #expect(wait.tick(missionControl: false) == .outOfSight)
        #expect(!wait.sawMissionControl)
        #expect(Double(WindowCoverage.OffScreenWait.settleTicks) * WindowCoverage.OffScreenWait.interval <= 0.5)
    }
}
