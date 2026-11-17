import CraCore
import Testing

/// `tabs of window` lists every space's tabs, as Arc 1.172.2 does (#428): the open space first,
/// in ⌘1…⌘9 order, then the others in space order, a shared favorite once.
@Suite struct AppleScriptTabOrderTests {
    static let lists: [String: [String]] = [
        "home": ["fav", "home-pinned", "home-today"],
        "work": ["fav", "work-pinned", "work-today"],
        "play": ["play-today"],
    ]
    static func order(focused: String) -> [String] {
        AppleScriptTabOrder.window(focused: focused, spaces: ["home", "work", "play"]) { lists[$0] ?? [] }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/428"))
    func listsEverySpaceOpenSpaceFirst() {
        #expect(Self.order(focused: "work") == ["fav", "work-pinned", "work-today", "home-pinned", "home-today", "play-today"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/428"))
    func keepsCommandDigitOrderAndSharedFavoritesOnce() {
        let list = Self.order(focused: "home")
        #expect(Array(list.prefix(3)) == Self.lists["home"])
        #expect(list.filter { $0 == "fav" }.count == 1)
        #expect(list.count == 6)
    }

    @Test func standaloneWindowListsItsOwnSpace() {
        #expect(AppleScriptTabOrder.window(focused: "play", spaces: ["play"]) { Self.lists[$0] ?? [] } == ["play-today"])
    }
}
