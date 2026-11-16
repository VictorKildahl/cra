import CoreGraphics
import Foundation

/// What asked a Peek to close: Arc 1.173.1's `ModalControllerAction.DismissMechanism`.
public enum PeekCloseAttempt: Equatable, Sendable {
    /// Esc. Arc's sender decides whether it asks for a confirmation first; Cra's never does, as Arc's
    /// rule for that wasn't found in its code.
    case escape(prefersConfirmation: Bool)
    case closeButton
    /// A click on the page around the card.
    case background
    /// ⌘W, Close Tab or Close Window.
    case closeShortcut
    case swipe
}

/// Why a Peek's close waits for a second one: Arc 1.173.1's `DismissConfirmationReason` (GitHub #425).
///
/// While it waits, the Close button widens into a red pill: Arc's `ModalV2ControlButton` expanded
/// config, the glyph where it was and "Confirm" after it, on `DestructiveButtonFace` in white. The pill
/// gives up after `timeout` and is the round button again. Arc reddens Close only here; under the
/// pointer it lifts as Expand and Add To Split do (PeekControlLook).
public enum PeekCloseHold: Equatable, Sendable {
    case escape
    /// The page is using the camera or microphone: closing the Peek would hang up its call.
    case mediaInput

    /// The next state after `attempt`, or nil when the Peek closes now. Arc's rule (the function that
    /// returns the reason, WindowData+ModalContent): while a pill is up, Esc, Close and ⌘W close; a
    /// click outside or a swipe keeps a call's pill and ends an Esc's. With no pill up, Esc waits only
    /// when it asks to, everything else only while the page uses the camera or microphone.
    public static func after(_ attempt: PeekCloseAttempt, holding: PeekCloseHold?, capturingMedia: Bool) -> PeekCloseHold? {
        if let holding {
            switch attempt {
            case .background, .swipe: return holding == .escape ? nil : holding
            case .escape, .closeButton, .closeShortcut: return nil
            }
        }
        switch attempt {
        case .escape(let prefersConfirmation): return prefersConfirmation ? .escape : nil
        case .closeButton, .closeShortcut, .background, .swipe: return capturingMedia ? .mediaInput : nil
        }
    }

    /// How long the pill waits for the second close (Arc's `dismissConfirmationReset`).
    public var timeout: TimeInterval { self == .mediaInput ? 10 : 1 }
    public var symbol: String { self == .mediaInput ? "phone.down.fill" : "xmark" }
    /// The pill's title (its tooltip): Arc's expanded config title.
    public var help: String { self == .mediaInput ? "Hang up" : "Close" }

    public static let text = "Confirm"
    /// Arc's `DestructiveButtonFace` (ARCUI asset catalog, one value for light and dark).
    public static let fill = RGB(0.961, 0.216, 0.078)
    public static let ink = RGB.white
    /// The text: `Font.system(size: 13, weight: .medium)`, sliding in from the leading edge as it fades in.
    public static let textSize: CGFloat = 13
    /// `ModalButtonStyle`'s padding around the label.
    public static let padding: CGFloat = 8
    /// The label's `HStack` spacing, glyph to text.
    public static let spacing: CGFloat = 4
    /// The pill opens and closes on this spring (`.animation(.spring(response: 0.25, dampingFraction: 0.8))`).
    public static let spring = PeekControlLook.Spring(response: 0.25, dampingFraction: 0.8)

    /// The pill's width: the round button's, then the spacing and the text. Its left edge stays put.
    public static func pillWidth(textWidth: CGFloat, button: CGSize) -> CGFloat {
        button.width + spacing + textWidth
    }

    /// Where the text starts, from the button's left edge.
    public static func textMinX(button: CGSize) -> CGFloat {
        button.width - padding + spacing
    }
}
