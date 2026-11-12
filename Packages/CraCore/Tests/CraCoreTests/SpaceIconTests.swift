import CraCore
import Foundation
import Testing

/// Edit Space… → Save turned an imported space's symbol into 🌱 stacked on the symbol (#205).
struct SpaceIconTests {
    static func space(emoji: String, symbol: String?) -> Space {
        Space(id: UUID(), title: "S", emoji: emoji, theme: SpaceColorPresets.newSpaceTheme(), favoritesContainerID: UUID(),
              pinnedContainerID: UUID(), todayContainerID: UUID(), createdAt: Date(timeIntervalSince1970: 0), symbol: symbol)
    }

    /// Edit Space… → Save leaves the icon as it was: a symbol, an emoji or none (#205).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/205"), arguments: [("", "square.on.square.fill"), ("🏠", nil), ("", nil)] as [(String, String?)])
    func savingTheIconItReadsChangesNothing(emoji: String, symbol: String?) {
        let space = Self.space(emoji: emoji, symbol: symbol)
        var saved = space
        saved.icon = space.icon
        #expect(saved == space)
    }

    /// Setting an icon writes both fields, so an emoji and a symbol never stack (#205).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/205"))
    func iconsNeverStack() {
        var s = Self.space(emoji: "", symbol: "star.fill")
        #expect(s.icon == .symbol("star.fill"))
        s.icon = .emoji("🌱")
        #expect(s.emoji == "🌱" && s.symbol == nil)
        s.icon = .symbol("leaf.fill")
        #expect(s.emoji == "" && s.symbol == "leaf.fill")
        s.icon = .none
        #expect(s.emoji == "" && s.symbol == nil)
    }

    /// Menus put the emoji before the name, and nothing before it for a symbol or no icon (#252).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/252"))
    func menuLabel() {
        #expect(Self.space(emoji: "🏠", symbol: nil).labeled == "🏠 S")
        #expect(Self.space(emoji: "", symbol: nil).labeled == "S")
        #expect(Self.space(emoji: "", symbol: "star.fill").labeled == "S")
    }

    /// A symbol wins over an emoji stored beside it; an empty symbol counts as none.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/205"))
    func readingTheStoredPair() {
        #expect(SpaceIcon(emoji: "🌱", symbol: "square.on.square.fill") == .symbol("square.on.square.fill"))
        #expect(SpaceIcon(emoji: "🌱", symbol: "") == .emoji("🌱"))
        #expect(SpaceIcon(emoji: "", symbol: nil) == .none)
        #expect(SpaceIcon.newSpace.emoji == "🌱" && SpaceIcon.newSpace.symbol == nil)
    }

    /// A picture icon survives a save and a JSON round trip, and never stacks with an emoji or symbol.
    @Test
    func aPictureIconRoundTrips() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        var s = Self.space(emoji: "🏠", symbol: "star.fill")
        s.icon = .image(png)
        #expect(s.emoji == "" && s.symbol == nil && s.iconImage == png)
        #expect(s.icon == .image(png))
        let back = try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(s))
        #expect(back.iconImage == png && back.icon == .image(png) && back.emoji == "" && back.symbol == nil)
        s.icon = .emoji("🌱")
        #expect(s.iconImage == nil)
        #expect(SpaceIcon(emoji: "🌱", symbol: "star.fill", image: png) == .image(png))
        #expect(SpaceIcon(emoji: "🌱", symbol: nil, image: Data()) == .emoji("🌱"))
    }

    /// A sidebar.json written before picture icons has no `iconImage` key and loads as before.
    @Test
    func olderSpacesHaveNoPicture() throws {
        let s = Self.space(emoji: "🏠", symbol: nil)
        let json = try JSONEncoder().encode(s)
        #expect(!String(decoding: json, as: UTF8.self).contains("iconImage"))
        #expect(try JSONDecoder().decode(Space.self, from: json).iconImage == nil)
    }
}
