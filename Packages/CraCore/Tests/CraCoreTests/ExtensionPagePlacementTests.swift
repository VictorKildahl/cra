import CraCore
import Foundation
import Testing

/// An extension's page opens in a space on the profile that asked, and an options page stays
/// one tab per profile, as in Arc (GitHub #107).
struct ExtensionPagePlacementTests {
    typealias P = ExtensionPagePlacement
    let a = P.Space(id: UUID(), profile: "Default")
    let b = P.Space(id: UUID(), profile: "Default")
    let work = P.Space(id: UUID(), profile: "Profile 1")
    let incognito = P.Space(id: UUID(), profile: "Default")
    let tabInA = UUID(), tabInB = UUID(), tabInWork = UUID()

    /// Arc: options open in space A, asked for again from space B, selects the tab in A.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/38"), .bug("https://github.com/VictorKildahl/cra/issues/107"))
    func openInAnotherSpaceOfTheProfileIsSelected() {
        let t = P.target(focused: b, spaces: [a, b, work], profile: "Default",
                         openTabs: [(tabInA, a.id)], singleton: true)
        #expect(t == .select(tab: tabInA))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/38"), .bug("https://github.com/VictorKildahl/cra/issues/107"))
    func openInThisSpaceWins() {
        let t = P.target(focused: b, spaces: [a, b], profile: nil,
                         openTabs: [(tabInA, a.id), (tabInB, b.id)], singleton: true)
        #expect(t == .select(tab: tabInB))
    }

    /// The report: Work (its own profile) asked, and the options tab open in a Default space
    /// pulled the window there, showing the Default profile's copy of the extension.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func anotherProfilesTabIsNeverReused() {
        #expect(P.target(focused: work, spaces: [a, b, work], profile: nil,
                         openTabs: [(tabInA, a.id)], singleton: true) == .create(inSpace: work.id))
        #expect(P.target(focused: a, spaces: [a, b, work], profile: nil,
                         openTabs: [(tabInWork, work.id)], singleton: true) == .create(inSpace: a.id))
    }

    /// chrome.tabs.create and welcome pages always get a tab of their own.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func otherPagesAlwaysOpenANewTab() {
        let t = P.target(focused: b, spaces: [a, b], profile: nil, openTabs: [(tabInB, b.id)], singleton: false)
        #expect(t == .create(inSpace: b.id))
    }

    /// Another profile's extension copy asked: its page loads in a space on that profile.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func anotherProfilesPageGoesToItsSpace() {
        #expect(P.target(focused: a, spaces: [a, b, work], profile: "Profile 1", openTabs: [], singleton: true)
            == .create(inSpace: work.id))
        #expect(P.target(focused: a, spaces: [a, b, work], profile: "Profile 1",
                         openTabs: [(tabInA, a.id), (tabInWork, work.id)], singleton: true) == .select(tab: tabInWork))
    }

    /// The page's profile has no space left: the space in front, as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func profileWithoutASpaceUsesTheFocusedOne() {
        #expect(P.target(focused: a, spaces: [a, b], profile: "Profile 9", openTabs: [], singleton: true) == .create(inSpace: a.id))
    }

    /// An incognito window never selects a normal tab (it can't show one).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"))
    func incognitoKeepsToItsOwnSpace() {
        #expect(P.target(focused: incognito, spaces: [a, b], profile: nil,
                         openTabs: [(tabInA, a.id)], singleton: true) == .create(inSpace: incognito.id))
    }
}
