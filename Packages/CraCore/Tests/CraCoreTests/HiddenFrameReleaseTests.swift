import CraCore
import Foundation
import Testing

/// Hidden tabs whose page windows draw once so Chromium's evicted frames release their tiles (#195).
struct HiddenFrameReleaseTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func tab(_ n: Int, minutesAgo: Double, released: Bool = false) -> HiddenFrameRelease.Tab {
        let hidden = now.addingTimeInterval(-minutesAgo * 60)
        return .init(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, hiddenAt: hidden, releasedFor: released ? hidden : nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func recentTabsWithinTheCapKeepTheirFrames() {
        let hidden = (1...4).map { tab($0, minutesAgo: Double($0)) }
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now).isEmpty)
    }

    /// Chromium keeps the 5 most recent frames (the visible tab's among them); older ones are evicted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func tabsPastTheCapAreDueOldestFirst() {
        let hidden = (1...12).map { tab($0, minutesAgo: Double($0) / 10) }
        let due = HiddenFrameRelease.due(hidden, visible: 1, now: now)
        #expect(due == hidden.suffix(8).map(\.id))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func tabsHiddenLongerThanTheCullAreDue() {
        let hidden = [tab(1, minutesAgo: 3), tab(2, minutesAgo: 11)]
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now) == [hidden[1].id])
    }

    /// Once drawn for this hiding, a tab isn't done again until it has been shown and hidden again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/195")) func eachHidingReleasesOnce() {
        let hidden = [tab(1, minutesAgo: 20, released: true), tab(2, minutesAgo: 20)]
        #expect(HiddenFrameRelease.due(hidden, visible: 1, now: now) == [hidden[1].id])
    }
}

/// The page window drawing for a release is never seen (#261): over a full-screen window a grey
/// pane flashed for a quarter second every minute or two, and Stage Manager showed a window come and go.
struct HiddenFrameReleaseWindowTests {
    /// The window as the window server has it.
    private struct Window {
        var onScreen = false
        var alpha = 1.0
        /// A child window of the browser window, ordered below it: it stays in the browser
        /// window's Space and under it, and Stage Manager doesn't list it.
        var childBelow = false
        var clickThrough = false

        /// A frame of it can show: drawn with any alpha, or on its own, where macOS puts it over a
        /// full-screen window or moves it out to a Space of its own and Stage Manager lists it.
        var seen: Bool { onScreen && (alpha > 0 || !childBelow) }

        mutating func apply(_ step: HiddenFrameRelease.WindowStep) {
            switch step {
            case .transparent: alpha = 0
            case .opaque: alpha = 1
            case .clickThrough(let on): clickThrough = on
            case .attachBelow: onScreen = true; childBelow = true
            case .detach: childBelow = false
            case .orderOut: onScreen = false; childBelow = false   // ordering a child out detaches it
            }
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/261")) func aWindowDrawingForAReleaseIsNeverSeen() {
        var w = Window()
        for step in HiddenFrameRelease.drawSteps + HiddenFrameRelease.doneSteps(shown: false) {
            w.apply(step)
            #expect(!w.seen, "seen after \(step)")
        }
        // Back as any hidden tab's window: off screen, opaque and clickable for when it's shown.
        #expect(!w.onScreen && w.alpha == 1 && !w.clickThrough && !w.childBelow)
    }

    /// The tab was selected during its quarter second: the window comes back as a page window,
    /// not a child below the browser window, so it is attached above like any other.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/261")) func aTabShownWhileDrawingComesBackOpaqueAndOnItsOwn() {
        var w = Window()
        for step in HiddenFrameRelease.drawSteps + HiddenFrameRelease.doneSteps(shown: true) { w.apply(step) }
        #expect(w.alpha == 1 && !w.clickThrough && !w.childBelow)
    }
}
