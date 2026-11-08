import CoreGraphics
import CraCore
import Testing

struct ExtensionBadgeTests {
    static let grey = ExtensionBadge.RGBA(r: 0.5, g: 0.5, b: 0.5)

    static func badge(_ text: String, color: String = "", textColor: String = "", width: Double) -> ExtensionBadge? {
        ExtensionBadge(state: ExtensionActionState(badgeText: text, badgeColor: color, badgeTextColor: textColor),
                       defaultBackground: grey) { _ in width }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func noTextNoBadge() {
        #expect(Self.badge("", color: "#FB8C00FF", width: 0) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func fortyTwoMatchesArc() throws {
        // Arc 1.171: "42" on a 16 pt icon is 8 × 7 pt, 1 pt in from the icon's bottom right.
        let b = try #require(Self.badge("42", color: "#FB8C00FF", width: 10.6))
        #expect(b.frame == CGRect(x: 7, y: 8, width: 8, height: 7))
        #expect(b.cutout == CGRect(x: 6.5, y: 7.5, width: 9, height: 8))
        #expect(b.cornerRadius == 2)
        #expect(b.cutoutCornerRadius == 1.5)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"), arguments: [
        // Never narrower than tall.
        (3.0, CGRect(x: 8, y: 8, width: 7, height: 7)),
        // Odd widths are made even, like the 28 pt icon area.
        (11.0, CGRect(x: 7, y: 8, width: 8, height: 7)),
        // 20 and wider (in Chromium's units) is centred, not right-aligned.
        (16.0, CGRect(x: 3, y: 8, width: 10, height: 7)),
        // Text wider than 23 is clipped to it.
        (40.0, CGRect(x: 1, y: 8, width: 14, height: 7)),
    ])
    func widthAndAlignment(textWidth: Double, frame: CGRect) throws {
        #expect(try #require(Self.badge("x", width: textWidth)).frame == frame)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func textContrastsWithTheBackground() throws {
        // Orange is light: Google Grey 900 text, as in Arc's capture.
        #expect(try #require(Self.badge("1", color: "#FB8C00FF", width: 5)).textColor == ExtensionBadge.RGBA(hex: "#202124"))
        #expect(try #require(Self.badge("1", color: "#1A73E8FF", width: 5)).textColor == ExtensionBadge.RGBA(r: 1, g: 1, b: 1))
        // chrome.action.setBadgeTextColor wins.
        #expect(try #require(Self.badge("1", color: "#FB8C00FF", textColor: "#FFFFFFFF", width: 5)).textColor
                == ExtensionBadge.RGBA(r: 1, g: 1, b: 1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/106"))
    func backgroundIsOpaqueOrTheDefault() throws {
        #expect(try #require(Self.badge("1", color: "#FF000080", width: 5)).background == ExtensionBadge.RGBA(r: 1, g: 0, b: 0))
        // Unset reaches Cra as transparent black.
        #expect(try #require(Self.badge("1", color: "#00000000", width: 5)).background == Self.grey)
        #expect(try #require(Self.badge("1", width: 5)).background == Self.grey)
    }
}
