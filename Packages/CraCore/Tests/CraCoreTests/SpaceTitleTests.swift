import CraCore
import Foundation
import Testing

/// A Space name has one user-facing limit at creation and rename. The limit counts Swift
/// Characters, so composed emoji and non-Latin names are not penalized by their UTF-8 size.
struct SpaceTitleTests {
    private func space(title: String) -> Space {
        Space(id: UUID(), title: title, emoji: "", theme: SpaceTheme.presets[0],
              favoritesContainerID: UUID(), pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: .now)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/471"))
    func creationDecodeAndEveryRenameShareAUnicodeSafeLimit() throws {
        #expect(Space.maximumTitleLength == 60)

        let exact = String(repeating: "a", count: Space.maximumTitleLength)
        let tooLong = exact + "b"
        #expect(space(title: exact).title == exact)
        #expect(space(title: tooLong).title == exact)

        var stored = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(space(title: "Home"))) as? [String: Any])
        stored["title"] = tooLong
        let decoded = try JSONDecoder().decode(Space.self, from: JSONSerialization.data(withJSONObject: stored))
        #expect(decoded.title == exact)

        var renamed = space(title: "Home")
        let unicode = String(repeating: "🧑‍💻", count: Space.maximumTitleLength + 1)
        renamed.rename(to: unicode)
        #expect(renamed.title == String(unicode.prefix(Space.maximumTitleLength)))
        #expect(renamed.title.count == Space.maximumTitleLength)

        renamed.title = tooLong
        #expect(renamed.title == exact)
    }
}
