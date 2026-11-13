import CoreGraphics
import Foundation

/// One of the round buttons beside a Peek card (Arc's `confirmCloseModal`, `openInSpaceExpander`
/// and `openInSplit`).
public enum PeekControl: String, CaseIterable, Sendable {
    case close, expand, addToSplit

    /// The button a menu or key action stands for while a Peek is key, so the shortcut presses it
    /// as a click would (GitHub #385): ⌘W is Close, ⌘O (Expand) is Expand. Add To Split has no
    /// shortcut, and every other action leaves the buttons alone.
    public static func pressed(byAction id: String) -> PeekControl? {
        switch id {
        case "closeTab", "closeWindow": .close
        case "promoteLittleWindow": .expand
        default: nil
        }
    }
}

/// How a Peek button looks under the pointer and while pressed: Arc 1.172.2's `ModalButtonStyle`
/// (GitHub #385, read from its `ButtonView.body`). At rest the button sits with a black shadow of
/// 20 % and radius 4, 1 pt down. Under the pointer it rises 1 pt and the shadow deepens to 30 % and
/// radius 6. Pressed it shrinks to 95 % about its centre and the shadow tightens back to radius 4.
public struct PeekControlLook: Equatable, Sendable {
    /// Points the button rises (Arc's `offset(y: -1)`).
    public var lift: CGFloat
    public var scale: CGFloat
    public var shadowOpacity: Double
    public var shadowRadius: CGFloat
    /// Points the shadow falls below the button, in every state.
    public static let shadowDrop: CGFloat = 1

    public init(lift: CGFloat, scale: CGFloat, shadowOpacity: Double, shadowRadius: CGFloat) {
        self.lift = lift
        self.scale = scale
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
    }

    public static func of(hovered: Bool, pressed: Bool) -> PeekControlLook {
        PeekControlLook(lift: hovered ? 1 : 0,
                        scale: pressed ? 0.95 : 1,
                        shadowOpacity: hovered ? 0.3 : 0.2,
                        shadowRadius: hovered && !pressed ? 6 : 4)
    }

    /// SwiftUI's `spring(response:dampingFraction:)` as Core Animation takes it (mass 1).
    public struct Spring: Equatable, Sendable {
        public var response: Double
        public var dampingFraction: Double
        public init(response: Double, dampingFraction: Double) {
            self.response = response
            self.dampingFraction = dampingFraction
        }
        public var stiffness: Double { pow(2 * .pi / response, 2) }
        public var damping: Double { 4 * .pi * dampingFraction / response }
    }

    /// The rise and the shadow follow the pointer on this spring (Arc's `.animation(_, value: isHovered)`).
    public static let hoverSpring = Spring(response: 0.15, dampingFraction: 0.95)
    /// A press and its release, the scale and the shadow with it (`.animation(_, value: isPressed)`).
    public static let pressSpring = Spring(response: 0.28, dampingFraction: 0.63)

    /// How long a button a shortcut pressed stays down before it springs back. The action runs at
    /// once; the Peek's closing picture, taken within 80 ms, shows the button pressed.
    public static let keyPressHold: TimeInterval = 0.15
}
