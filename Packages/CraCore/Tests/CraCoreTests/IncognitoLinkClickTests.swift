import CraCore
import Testing

struct IncognitoLinkClickTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/907"))
    func onlyShiftClicksOpenAnIncognitoTab() {
        #expect(IncognitoLinkClick.opensTab(shiftClick: true, newTab: false))
        #expect(!IncognitoLinkClick.opensTab(shiftClick: false, newTab: false))
        #expect(!IncognitoLinkClick.opensTab(shiftClick: false, newTab: true))
        #expect(!IncognitoLinkClick.opensTab(shiftClick: true, newTab: true))
    }
}
