import CraCore
import Testing

/// The address a Little Window loads again when its address pill moves the page to another profile.
struct LittleProfileChangeTests {
    let link = "https://tracker.example.com/issues/42"
    let signIn = "https://accounts.google.com/v3/signin/identifier?challenge=abc"
    let next = "https://tracker.example.com/issues/43"

    /// A link whose redirects ended on a sign-in page of the first profile: the other profile opens
    /// the link, not that sign-in page, whose challenge belongs to the first profile's session.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/763")) func theLinkOpensAgainNotWhereItsRedirectsEnded() {
        #expect(LittleProfileChange.address(opened: link, shown: signIn, wentOn: false) == link)
    }

    /// A link clicked in the page after it opened: the page the user went on to opens, not the
    /// window's first link.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/763")) func aPageGoneOnFromItsLinkKeepsThePageShown() {
        #expect(LittleProfileChange.address(opened: link, shown: next, wentOn: true) == next)
    }

    /// A popup host or the empty card opened with no address of its own: the page shown, or a blank
    /// page when there is none.
    @Test func withoutAnOpeningAddressThePageShownOpens() {
        #expect(LittleProfileChange.address(opened: nil, shown: signIn, wentOn: false) == signIn)
        #expect(LittleProfileChange.address(opened: "", shown: signIn, wentOn: false) == signIn)
        #expect(LittleProfileChange.address(opened: "about:blank", shown: "", wentOn: false) == "about:blank")
        #expect(LittleProfileChange.address(opened: nil, shown: "about:blank", wentOn: false) == "about:blank")
    }

    /// A link still waiting for its first answer has no page to show yet: the link opens.
    @Test func aLinkStillLoadingOpensAgain() {
        #expect(LittleProfileChange.address(opened: link, shown: "", wentOn: false) == link)
    }
}
