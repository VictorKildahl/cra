import CraCore
import Foundation
import Testing

struct AutoPictureInPictureMomentTests {
    /// Arc opens the automatic Picture in Picture on a tab switch, not on a space switch (#703).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/703"))
    func aTabSwitchOpensItAndASpaceSwitchDoesNot() {
        let home = UUID(), work = UUID()
        #expect(AutoPictureInPictureMoment.opensOnLeaving(from: home, to: home), "another tab in the same space")
        #expect(!AutoPictureInPictureMoment.opensOnLeaving(from: home, to: work), "another space")
        #expect(AutoPictureInPictureMoment.opensOnLeaving(from: nil, to: home), "the window's first pages")
    }
}
