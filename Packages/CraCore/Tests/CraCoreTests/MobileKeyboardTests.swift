import CoreGraphics
import CraCore
import Testing

/// How much of the iPhone app's screen the keyboard covers, from UIKit's keyboard notifications.
/// The bottom bar steps aside while the page's keyboard is up, so a keyboard that is gone but still
/// counted keeps the bar off screen.
struct MobileKeyboardTests {
    /// An iPhone 17: 402 × 874 pt, a 336 pt keyboard.
    let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
    let up = CGRect(x: 0, y: 538, width: 402, height: 336)

    @Test func aKeyboardThatSlidesInAndOutCoversItsHeightThenNothing() {
        var keyboard = MobileKeyboard()
        #expect(keyboard.height(in: screen) == 0)
        keyboard.apply(.willChangeFrame, endFrame: up)
        keyboard.apply(.willShow, endFrame: up)
        #expect(keyboard.height(in: screen) == 336)
        let below = up.offsetBy(dx: 0, dy: 336)
        keyboard.apply(.willChangeFrame, endFrame: below)
        keyboard.apply(.willHide, endFrame: below)
        #expect(keyboard.height(in: screen) == 0)
    }

    /// iOS 27.2 on an iPhone 17 fades the keyboard out where it is when the search sheet closes:
    /// its last frame is still on screen, and only the hide says it is gone. The bar stayed down on
    /// every page after a search, with Collapse Bottom Bar on or off.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/505"))
    func aKeyboardThatFadesOutWhereItIsCoversNothing() {
        var keyboard = MobileKeyboard()
        keyboard.apply(.willShow, endFrame: up)
        keyboard.apply(.willChangeFrame, endFrame: up)
        keyboard.apply(.willHide, endFrame: up)
        #expect(keyboard.height(in: screen) == 0)

        var late = MobileKeyboard()
        late.apply(.willShow, endFrame: up)
        late.apply(.willHide, endFrame: up)
        late.apply(.willChangeFrame, endFrame: up)
        #expect(late.height(in: screen) == 0)
        late.apply(.didHide, endFrame: up)
        #expect(late.height(in: screen) == 0)
    }

    /// A hide can come with an empty frame; it covers nothing, not the whole screen.
    @Test func anEmptyFrameCoversNothing() {
        var keyboard = MobileKeyboard()
        keyboard.apply(.willShow, endFrame: up)
        keyboard.apply(.willChangeFrame, endFrame: .zero)
        #expect(keyboard.height(in: screen) == 0)
    }

    /// The keyboard comes back up after a hide, and a frame partly below the screen covers only
    /// what is on it.
    @Test func showingAgainCoversWhatIsOnScreen() {
        var keyboard = MobileKeyboard()
        keyboard.apply(.willShow, endFrame: up)
        keyboard.apply(.didHide, endFrame: up)
        keyboard.apply(.willShow, endFrame: up.offsetBy(dx: 0, dy: 100))
        #expect(keyboard.height(in: screen) == 236)
    }
}
