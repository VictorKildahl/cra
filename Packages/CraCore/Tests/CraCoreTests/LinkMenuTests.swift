import Testing
import CraCore
import Foundation

@Suite struct LinkMenuTests {
    /// Arc's page menu has one "Open Link in New Tab", and the page stays in front (#276, measured
    /// in Arc 1.172): Cra's did switch, with "Open Link in Background Tab" under it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func oneItemThatOpensBehindThePageLikeArc() {
        let item = LinkMenu.item(switchesToTab: false)
        #expect(item.title == "Open Link in New Tab" && item.opensInBackground)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func settingOnSwitchesToTheNewTab() {
        let item = LinkMenu.item(switchesToTab: true)
        #expect(item.title == "Open Link in New Tab" && !item.opensInBackground)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/276"))
    func newTabItemIsChromiumsOwnLabel() {
        for switches in [false, true] {
            let item = LinkMenu.item(switchesToTab: switches, newTabTitle: "Открыть ссылку в новой вкладке")
            #expect(item.title == "Открыть ссылку в новой вкладке" && item.opensInBackground == !switches)
        }
    }
}
