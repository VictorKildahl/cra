import CoreGraphics
import Foundation

/// What asked a Peek to close: Arc 1.173.1's `ModalControllerAction.DismissMechanism`.
public enum PeekCloseAttempt: Equatable, Sendable {
    /// Esc. Arc's sender decides whether it asks for a confirmation first (its rule wasn't found in
    /// Arc's code); Cra's asks when the page kept the Esc (PeekEscapePresses, #520).
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

/// Esc in a Peek (GitHub #520). The page sees it first, and an Esc the page leaves alone closes the
/// Peek. A page that keeps every Esc (Gmail cancels each one, with nothing of its own open) would hold
/// the Peek open for good, so an Esc it hasn't handed back after `answerTime` turns Close into Arc's
/// Confirm pill (`escape(prefersConfirmation: true)`). The next Esc, while the pill is up or before
/// the page has handed the last one back, is Cra's before the page sees it and closes. A page that
/// uses Esc for its own menu or dialog keeps that one.
public struct PeekEscapePresses: Equatable, Sendable {
    /// How long a page has to hand an Esc back before Cra counts it as the page's (as for Use Both).
    public static let answerTime = UseBothPresses.answerTime

    /// The press the page has and hasn't handed back yet (its event timestamp).
    private(set) var waiting: TimeInterval?

    public init() {}

    /// The key a Peek acts on: Esc (key code 53) with none of ⇧⌃⌥⌘ held (`modifiers` are NSEvent's
    /// flag bits; Caps Lock and fn don't count). ⇧Esc and the rest are the page's or another shortcut's.
    public static func isEscape(keyCode: UInt16, modifiers: UInt) -> Bool {
        keyCode == 53 && KeyChord.Modifiers(rawValue: modifiers).isDisjoint(with: [.shift, .control, .option, .command])
    }

    /// An Esc before the page sees it, at `time` (the event's timestamp): true when Cra takes it and
    /// the Peek closes. A pill is up (Esc closes any pill, Arc), or the last Esc hasn't come back from
    /// the page: a double Esc closes without waiting for the pill. A held Esc's repeats go where the
    /// first went.
    public mutating func beforePage(at time: TimeInterval, holding: PeekCloseHold?, isRepeat: Bool) -> Bool {
        if isRepeat { return false }
        if holding != nil || waiting != nil {
            waiting = nil
            return true
        }
        waiting = time
        return false
    }

    /// The page left the Esc alone (it closes the Peek): nothing to ask.
    public mutating func pageLeft() { waiting = nil }

    /// `answerTime` after the Esc at `pressedAt`: true when the page kept it, and Close asks. A pill
    /// that came up meanwhile (`holding`, a call's after ⌘W) stays as it is, and the Esc is forgotten.
    public mutating func pageKept(pressedAt: TimeInterval, holding: PeekCloseHold?) -> Bool {
        guard waiting == pressedAt else { return false }
        waiting = nil
        return holding == nil
    }
}
