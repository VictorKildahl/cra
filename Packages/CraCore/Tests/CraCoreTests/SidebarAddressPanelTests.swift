import Testing
@testable import CraCore

/// Arc's address panel from the sidebar (#663), as measured in offline Arc 1.174.
struct SidebarAddressPanelTests {
    /// Arc's field for addresses of 22 to 101 characters (their widths in 13 pt medium) and its panel:
    /// 240 for short ones, the text's width as it grows, 610 at most; the panel 110 more.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/663"),
          arguments: [(0.0, 350.0), (160.0, 350.0), (244.9, 356.9), (387.7, 499.7), (667.8, 720.0)])
    func widthFollowsTheAddress(textWidth: Double, panel: Double) {
        #expect(abs(SidebarAddressPanel.width(textWidth: textWidth, available: 1700) - panel) < 0.01)
    }

    /// Arc's rows on its 50 pt pitch under a 45 pt input row: five rows make a 307.5 pt panel (Arc:
    /// 45 to 352.5 in the window); no rows leave the input row.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/663"))
    func heightHoldsTheRows() {
        #expect(SidebarAddressPanel.height(rows: 5) == 307.5)
        #expect(SidebarAddressPanel.height(rows: 0) == SidebarAddressPanel.inputHeight)
        #expect(SidebarAddressPanel.height(rows: 1) == 45 + 6 + 46 + 10.5)
    }

    /// A narrow window keeps the panel inside it, 8 pt from its edge.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/663"))
    func narrowWindowKeepsItInside() {
        #expect(SidebarAddressPanel.width(textWidth: 667.8, available: 500) == 492)
        #expect(SidebarAddressPanel.width(textWidth: 0, available: 5) == 0)
    }
}
