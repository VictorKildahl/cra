import CraCore
import Foundation
import Testing

/// The menu bar's Spaces rows follow the real Spaces, while only the first nine carry the
/// customizable positional shortcuts (GitHub #471).
struct SpacesMenuCompositionTests {
    private func ids(_ count: Int) -> [UUID] {
        (1...count).map { UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", $0))! }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/471"))
    func navigationContainsEveryRealSpaceInOrder() {
        for count in [1, 2, 9, 10] {
            let spaces = ids(count)
            let composition = SpacesMenuComposition(spaceIDs: spaces)

            #expect(composition.navigation.map(\.spaceID) == spaces)
            #expect(composition.navigation.map(\.position) == Array(1...count))

            let navigationShortcuts: [String?] = (1...count).map { $0 <= 9 ? "space\($0)" : nil }
            #expect(composition.navigation.map(\.shortcutID) == navigationShortcuts)
        }
    }

    @Test func reorderedSpacesStayInMenuOrder() {
        let spaces = ids(3).reversed()
        let composition = SpacesMenuComposition(spaceIDs: Array(spaces))

        #expect(composition.navigation.map(\.spaceID) == Array(spaces))
    }

    @Test func addingDeletingAndReorderingRecomposesEveryRow() {
        let all = ids(3)
        var spaces = Array(all.prefix(2))

        #expect(SpacesMenuComposition(spaceIDs: spaces).navigation.map(\.spaceID) == [all[0], all[1]])
        spaces.append(all[2])
        #expect(SpacesMenuComposition(spaceIDs: spaces).navigation.map(\.spaceID) == all)
        spaces = [all[2], all[0], all[1]]
        #expect(SpacesMenuComposition(spaceIDs: spaces).navigation.map(\.spaceID) == [all[2], all[0], all[1]])
        spaces.removeFirst()
        #expect(SpacesMenuComposition(spaceIDs: spaces).navigation.map(\.spaceID) == [all[0], all[1]])
    }
}
