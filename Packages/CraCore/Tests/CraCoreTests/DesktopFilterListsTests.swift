import CraCore
import Foundation
import Testing

struct DesktopFilterListsTests {
    @Test func catalogUsesUniqueHTTPSAddresses() {
        let addresses = DesktopFilterList.catalog.map(\.address)
        #expect(addresses.count == Set(addresses).count)
        #expect(addresses.allSatisfy { CustomBlocklist.listURL(from: $0)?.scheme == "https" })
    }

    @Test func hostProjectionDoesNotWidenScopedFilters() {
        let list = DesktopHidingRules.read("""
        ||tracker.example^$third-party
        ||cdn.example^$script
        ||excepted.example^
        @@||media.excepted.example/allowed.png
        !#if ext_ublock
        ||conditional.example^
        ##.conditional
        !#endif
        """, address: "fixture", fetched: .distantPast)
        #expect(list.domains == ["tracker.example"])
        #expect(list.hidingRules.isEmpty)
    }

    @Test func hidingAndExceptionsUseDomainBoundaries() {
        let list = DesktopHidingRules.read("""
        ||tracker.example^
        ##.sponsor
        host.example#@#.sponsor
        host.example,~private.host.example###notice
        ##div[id^="ad_"]
        ##+js(script)
        ##.unsafe{color:red}
        """, address: "https://lists.example/list", fetched: Date(timeIntervalSince1970: 10))
        #expect(list.domains == ["tracker.example"])
        #expect(list.hidingRules.count == 4)
        #expect(list.skippedRules == 2)
        #expect(CachedBlocklist(text: list.text) == list)
        let hides = DesktopHidingRules(lines: list.hidingRules)
        #expect(hides.css(host: "badhost.example").contains(".sponsor{"))
        #expect(!hides.css(host: "sub.host.example").contains(".sponsor{"))
        #expect(hides.css(host: "sub.host.example").contains("#notice{"))
        #expect(!hides.css(host: "private.host.example").contains("#notice{"))
        #expect(hides.css(host: "host.example").contains("div[id^=\"ad_\"]{"))
        #expect(!hides.css(host: "host.example").contains("color:red"))
    }
}
