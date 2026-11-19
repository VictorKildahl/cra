import CoreGraphics
import CraCore
import Foundation
import Testing

/// Whether a browser window is out of sight, for automatic Picture in Picture when it isn't key
/// (#533). macOS's occlusion state says "not visible" first; the windows in front of it decide.
@Suite struct WindowCoverageTests {
    typealias Above = WindowCoverage.Above
    /// A window on a second display, below and right of a 1728 × 1117 built-in one (CG's top-left origin).
    static let frame = CGRect(x: 1728, y: 0, width: 1400, height: 880)

    struct Case: Sendable {
        var name: String
        var onScreen = true
        var above: [Above]
        var covered: Bool
    }

    static let cases: [Case] = [
        // #533: Cra on a second display, another app made active on the first. Chrome's page host window
        // (alpha 0, the main window's own frame, in front of it) and the window's child windows are parts
        // of it; on macOS 27.2.1 the window still went to Picture in Picture.
        .init(name: "nothing in front", above: [], covered: false),
        .init(name: "page host window over it", above: [.init(frame: frame, alpha: 0, isOwnPart: true)], covered: false),
        .init(name: "own child windows over all of it", above: [.init(frame: frame, alpha: 1, isOwnPart: true)], covered: false),
        .init(name: "see-through window of another app", above: [.init(frame: frame, alpha: 0, isOwnPart: false)], covered: false),
        .init(name: "another app on the other display",
              above: [.init(frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), alpha: 1, isOwnPart: false)], covered: false),
        .init(name: "another app over part of it",
              above: [.init(frame: CGRect(x: 1728, y: 0, width: 1000, height: 880), alpha: 1, isOwnPart: false)], covered: false),
        .init(name: "another app over the rest, its own page window over the sidebar", above: [
            .init(frame: CGRect(x: 1728, y: 0, width: 300, height: 880), alpha: 1, isOwnPart: true),
            .init(frame: CGRect(x: 2028, y: 0, width: 1100, height: 880), alpha: 1, isOwnPart: false),
        ], covered: false),
        .init(name: "another app over all but a 3 pt strip",
              above: [.init(frame: CGRect(x: 1731, y: 0, width: 1397, height: 880), alpha: 1, isOwnPart: false)], covered: false),
        .init(name: "a see-through window and an app over half",
              above: [.init(frame: frame, alpha: 0, isOwnPart: false),
                      .init(frame: CGRect(x: 1728, y: 0, width: 700, height: 880), alpha: 1, isOwnPart: false)], covered: false),
        // Out of sight: as before #533.
        .init(name: "another app over all of it", above: [.init(frame: frame.insetBy(dx: -20, dy: -20), alpha: 1, isOwnPart: false)], covered: true),
        .init(name: "a faded window over all of it", above: [.init(frame: frame, alpha: 0.2, isOwnPart: false)], covered: true),
        .init(name: "two apps over it between them", above: [
            .init(frame: CGRect(x: 1728, y: 0, width: 800, height: 880), alpha: 1, isOwnPart: false),
            .init(frame: CGRect(x: 2500, y: -10, width: 700, height: 900), alpha: 0.95, isOwnPart: false),
        ], covered: true),
        .init(name: "two apps with a 1 pt gap between them", above: [
            .init(frame: CGRect(x: 1728, y: 0, width: 1400, height: 439), alpha: 1, isOwnPart: false),
            .init(frame: CGRect(x: 1728, y: 440, width: 1400, height: 440), alpha: 1, isOwnPart: false),
        ], covered: true),
        .init(name: "another app over all but a 1 pt strip (a shadow, a rounding)",
              above: [.init(frame: CGRect(x: 1729, y: 0, width: 1399, height: 880), alpha: 1, isOwnPart: false)], covered: true),
        .init(name: "another app given with a negative size", above: [.init(frame: CGRect(x: 3128, y: 880, width: -1400, height: -880), alpha: 1, isOwnPart: false)], covered: true),
        .init(name: "minimised, hidden or on another desktop", onScreen: false, above: [], covered: true),
        .init(name: "not on screen, its page window still listed", onScreen: false,
              above: [.init(frame: frame, alpha: 0, isOwnPart: true)], covered: true),
    ]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/533"), arguments: cases)
    func covered(_ c: Case) {
        #expect(WindowCoverage.isCovered(frame: Self.frame, onScreen: c.onScreen, above: c.above) == c.covered, "\(c.name)")
    }

    // MARK: The window server's list

    static let pid: Int32 = 54281, other: Int32 = 911

    /// An entry as `CGWindowListCopyWindowInfo` gives it: NSNumbers, bounds as a dictionary, and no
    /// `kCGWindowIsOnscreen` for a window that isn't on screen.
    static func info(_ number: Int, pid: Int32, _ r: CGRect, alpha: Double = 1, onScreen: Bool = true) -> [String: Any] {
        var d: [String: Any] = [
            "kCGWindowNumber": NSNumber(value: number), "kCGWindowOwnerPID": NSNumber(value: pid),
            "kCGWindowAlpha": NSNumber(value: alpha), "kCGWindowLayer": NSNumber(value: 0),
            "kCGWindowBounds": ["X": NSNumber(value: Double(r.minX)), "Y": NSNumber(value: Double(r.minY)),
                                "Width": NSNumber(value: Double(r.width)), "Height": NSNumber(value: Double(r.height))] as NSDictionary,
        ]
        if onScreen { d["kCGWindowIsOnscreen"] = NSNumber(value: true) }
        return d
    }

    /// Cra's windows as the list showed them on 18 Nov 2026 (0.1.48): the main window, and Chrome's page
    /// host window in front of it with the same frame and alpha 0.
    static let main = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    static let host = 87010

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/533"))
    func pageHostWindowInFrontIsTheWindowsOwn() {
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(Self.host, pid: Self.pid, Self.main, alpha: 0),
                                              Self.info(501, pid: Self.other, CGRect(x: 1728, y: 0, width: 1920, height: 1080))],
                                    pid: Self.pid, isOwnPart: { $0 == Self.host })
        #expect(r == .init(covered: false, onScreen: true, inFront: 2, ownParts: 1, seeThrough: 1))
        #expect(r.summary == "on screen, 2 in front (1 own parts, 1 see-through), not covered")
    }

    @Test func anotherAppOverItCovers() {
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(Self.host, pid: Self.pid, Self.main, alpha: 0),
                                              Self.info(501, pid: Self.other, CGRect(x: 0, y: 25, width: 1728, height: 1092))],
                                    pid: Self.pid, isOwnPart: { $0 == Self.host })
        #expect(r.covered)
        #expect(r.ownParts == 1)
    }

    /// The readout names other apps' windows over it by owner and layer, and leaves out see-through ones, ones
    /// elsewhere on screen and Cra's own: on Nightly's runners something covered the window (#533).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/533")) func summaryNamesWhatIsOverIt() {
        var finder = Self.info(501, pid: Self.other, CGRect(x: 0, y: 25, width: 1728, height: 1092))
        finder["kCGWindowOwnerName"] = "Finder"
        finder["kCGWindowLayer"] = NSNumber(value: 3)
        var clear = Self.info(502, pid: Self.other, Self.main, alpha: 0)
        clear["kCGWindowOwnerName"] = "Clear"
        var away = Self.info(503, pid: Self.other, CGRect(x: 5000, y: 0, width: 100, height: 100))
        away["kCGWindowOwnerName"] = "Away"
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(Self.host, pid: Self.pid, Self.main, alpha: 0), finder, clear, away],
                                    pid: Self.pid, isOwnPart: { $0 == Self.host })
        #expect(r.overlapping == ["Finder@3"])
        #expect(r.summary == "on screen, 4 in front (1 own parts, 2 see-through), covered, over it: Finder@3")
    }

    /// The Dock's window spans its display at layer 20 and is clear apart from the Dock: on Nightly's runners it was the
    /// only other window over Cra's, which counted as covered and sent its video to Picture in Picture (#533).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/533")) func theDocksWindowCoversNothing() {
        var dock = Self.info(601, pid: Self.other, CGRect(x: 0, y: 0, width: 1728, height: 1117))
        dock["kCGWindowOwnerName"] = "Dock"
        dock["kCGWindowLayer"] = NSNumber(value: 20)
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(Self.host, pid: Self.pid, Self.main, alpha: 0), dock],
                                    pid: Self.pid, isOwnPart: { $0 == Self.host })
        #expect(!r.covered)
        #expect(r.overlapping.isEmpty)
    }

    /// Another of Cra's own browser windows is in front, not a part of this one: it covers like any app.
    @Test func anotherCraWindowCovers() {
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(90000, pid: Self.pid, Self.main)],
                                    pid: Self.pid, isOwnPart: { $0 == Self.host })
        #expect(r.covered)
        #expect(r.ownParts == 0)
    }

    /// Only this process's windows are asked about: another app's window with the host's number is not ours.
    @Test func otherAppsWindowNumbersAreNotAsked() {
        var asked: [Int] = []
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main),
                                    inFront: [Self.info(Self.host, pid: Self.other, Self.main)],
                                    pid: Self.pid, isOwnPart: { asked.append($0); return true })
        #expect(asked.isEmpty)
        #expect(r.covered)
    }

    @Test func notOnScreenWhenTheListLeavesTheKeyOut() {
        let r = WindowCoverage.read(window: Self.info(87008, pid: Self.pid, Self.main, onScreen: false), inFront: [],
                                    pid: Self.pid, isOwnPart: { _ in false })
        #expect(r == .init(covered: true, onScreen: false, inFront: 0, ownParts: 0, seeThrough: 0))
        #expect(r.summary == "not on screen, covered")
    }

    /// No entry for the window (it went away in between): out of sight, as macOS said.
    @Test func noEntryKeepsWhatMacOSSaid() {
        #expect(WindowCoverage.read(window: nil, inFront: [], pid: Self.pid, isOwnPart: { _ in false }).covered)
        #expect(WindowCoverage.read(window: ["kCGWindowNumber": NSNumber(value: 1)], inFront: [], pid: Self.pid, isOwnPart: { _ in false }).covered)
    }

    /// Entries without bounds are skipped, and a missing alpha is 1.
    @Test func entriesParseAsTheListGivesThem() throws {
        let plain: [String: Any] = ["kCGWindowNumber": 7, "kCGWindowOwnerPID": 9,
                                    "kCGWindowBounds": ["X": 1.5, "Y": 2, "Width": 30, "Height": 40] as [String: Any]]
        let w = try #require(WindowCoverage.Listed(plain))
        #expect(w == .init(number: 7, ownerPID: 9, frame: CGRect(x: 1.5, y: 2, width: 30, height: 40), alpha: 1, onScreen: false))
        #expect(WindowCoverage.Listed(["kCGWindowNumber": 7, "kCGWindowOwnerPID": 9]) == nil)
        #expect(WindowCoverage.Listed(Self.info(3, pid: 4, Self.main, alpha: 0))?.alpha == 0)
    }
}

extension WindowCoverageTests.Case: CustomTestStringConvertible {
    var testDescription: String { name }
}
