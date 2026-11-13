import CraCore
import Foundation
import Testing

/// A page made ahead for the next tab that needs one, so a new tab doesn't wait for CEF's window.
struct SparePageTests {
    @Test func onlyChromiumPagesInAProfile() {
        #expect(SparePage.canTake(engine: .chromium, isEasel: false, incognito: false))
        // A DRM service's tab opens in WebKit; an easel is Cra's canvas; incognito has no profile.
        #expect(!SparePage.canTake(engine: .webKit, isEasel: false, incognito: false))
        #expect(!SparePage.canTake(engine: .chromium, isEasel: true, incognito: false))
        #expect(!SparePage.canTake(engine: .chromium, isEasel: false, incognito: true))
    }

    @Test func onePerProfile() {
        #expect(SparePage.key(profilePath: nil) == "")
        #expect(SparePage.key(profilePath: "/p/Work") == "/p/Work")
        #expect(SparePage.key(profilePath: "/p/Work") != SparePage.key(profilePath: nil))
    }

    @Test func refillsAfterTheClick() {
        #expect(SparePage.refillDelay >= 1)
    }
}
