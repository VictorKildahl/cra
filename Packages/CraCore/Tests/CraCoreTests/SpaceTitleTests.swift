import CraCore
import Foundation
import Testing

/// A Space name has one user-facing limit at creation and rename. The limit counts Swift
/// Characters, so composed emoji and non-Latin names are not penalized by their UTF-8 size.
/// A longer name already on disk (saved before the limit, or synced) loads unchanged.
struct SpaceTitleTests {
    private func space(title: String) -> Space {
        Space(id: UUID(), title: title, emoji: "", theme: SpaceTheme.presets[0],
              favoritesContainerID: UUID(), pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: .now)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/471"))
    func creationAndEveryRenameShareAUnicodeSafeLimit() throws {
        #expect(Space.maximumTitleLength == 60)

        let exact = String(repeating: "a", count: Space.maximumTitleLength)
        let tooLong = exact + "b"
        #expect(space(title: exact).title == exact)
        #expect(space(title: tooLong).title == exact)

        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(space(title: "Home"))) as? [String: Any])
        stored["title"] = tooLong
        let decoded = try JSONDecoder().decode(Space.self, from: JSONSerialization.data(withJSONObject: stored))
        #expect(decoded.title == tooLong, "a stored name loads as saved, so loading never shortens it on disk")

        var renamed = space(title: "Home")
        let unicode = String(repeating: "🧑‍💻", count: Space.maximumTitleLength + 1)
        renamed.rename(to: unicode)
        #expect(renamed.title == String(unicode.prefix(Space.maximumTitleLength)))
        #expect(renamed.title.count == Space.maximumTitleLength)

        renamed.title = tooLong
        #expect(renamed.title == exact)
    }
}
