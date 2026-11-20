import CraCore
import Foundation
import Testing

/// Change Icon… on a favorite or a tab: Arc's Emoji | Icon picker (GitHub #640).
struct TabCustomIconTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/640"))
    func eachPickHasAKeyOfItsOwnAndRemoveGoesBackToTheSite() {
        #expect(TabCustomIcon.keyPrefix(for: .emoji("🍕")) == "custom-emoji-")
        #expect(TabCustomIcon.keyPrefix(for: .symbol("star.fill")) == "custom-symbol-")
        #expect(TabCustomIcon.keyPrefix(for: .image(Data([1]))) == "custom-")
        #expect(TabCustomIcon.keyPrefix(for: .none) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/640"))
    func onlyASymbolFollowsTheSpacesTheme() {
        #expect(TabCustomIcon.followsTheme(key: "custom-symbol-1"))
        #expect(!TabCustomIcon.followsTheme(key: "custom-emoji-1"))
        #expect(!TabCustomIcon.followsTheme(key: "custom-1"))
    }
}
