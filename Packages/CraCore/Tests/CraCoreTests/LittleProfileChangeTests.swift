import CraCore
import Testing

/// The address a Little Window loads again when its address pill moves the page to another profile.
struct LittleProfileChangeTests {
    let link = "https://tracker.example.com/issues/42"
    let signIn = "https://accounts.google.com/v3/signin/identifier?challenge=abc"

    /// A link whose redirects ended on a sign-in page of the first profile: the other profile opens
    /// the link, not that sign-in page, whose challenge belongs to the first profile's session.
    @Test func theLinkOpensAgainNotWhereItsRedirectsEnded() {
        #expect(LittleProfileChange.address(opened: link, shown: signIn) == link)
    }

    /// A popup host or the empty card opened with no address of its own: the page shown, or a blank
    /// page when there is none.
    @Test func withoutAnOpeningAddressThePageShownOpens() {
        #expect(LittleProfileChange.address(opened: nil, shown: signIn) == signIn)
        #expect(LittleProfileChange.address(opened: "", shown: signIn) == signIn)
        #expect(LittleProfileChange.address(opened: "about:blank", shown: "") == "about:blank")
        #expect(LittleProfileChange.address(opened: nil, shown: "about:blank") == "about:blank")
    }

    /// A link still waiting for its first answer has no page to show yet: the link opens.
    @Test func aLinkStillLoadingOpensAgain() {
        #expect(LittleProfileChange.address(opened: link, shown: "") == link)
    }
}
