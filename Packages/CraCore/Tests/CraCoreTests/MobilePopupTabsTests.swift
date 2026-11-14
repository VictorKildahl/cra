import Foundation
import Testing
@testable import CraCore

struct MobilePopupTabsTests {
    @Test func onlyTheSelectedPopupsLivePrivateOpenersStayOpen() {
        let first = MobileTab(url: "https://private.example/", lastActive: .distantPast, isIncognito: true)
        let second = MobileTab(url: "https://private.example/popup", lastActive: .distantPast, isIncognito: true)
        let unrelated = MobileTab(url: "https://public.example/", lastActive: .distantPast)
        var document = MobileTabsDocument(tabs: [first, second, unrelated], selected: second.id)
        #expect(document.closeIncognitoTabsLeftBehind(keeping: [first.id]).isEmpty)
        #expect(document.tabs.map(\.id) == [first.id, second.id, unrelated.id])
        document.select(unrelated.id, now: .distantFuture)
        #expect(Set(document.closeIncognitoTabsLeftBehind()) == [first.id, second.id])
        #expect(document.tabs.map(\.id) == [unrelated.id])
        #expect(document.archived.isEmpty)
    }
}
