import CoreGraphics

/// What kind of screen the iPhone app is on, for the layouts that differ (#866). The open iPhone Duo (951 × 669 pt) is
/// an iPhone with a screen the size of a small iPad, which Arc Search never had: Victor's call (27 Nov 2026) was to treat
/// it like a small iPad, as 0xJeu proposed. Its sheets open at full height as on iPad, and the bottom bar's buttons and
/// the tab switcher's row keep to the middle. The closed Duo (466 pt across) and an iPhone on its side (about 400 pt
/// tall) stay phones; an iPad keeps its own layout.
public enum MobileScreenClass: Equatable, Sendable {
    case phone, wide, pad

    /// A screen whose short side is at least this is no phone's.
    public static let wideShortSide: CGFloat = 600
    /// SheetHost's cap on content across a wide screen.
    public static let contentCap: CGFloat = 540
    /// The widest iPhone's screen (the Pro Max's 440 pt): the tab row's width on a wide screen.
    public static let phoneWidth: CGFloat = 440

    public static func of(size: CGSize, isPad: Bool) -> MobileScreenClass {
        if isPad { return .pad }
        return min(size.width, size.height) >= wideShortSide ? .wide : .phone
    }

    /// App Settings and the App Icon picker open at full height rather than half (#674 on iPad).
    public var opensSheetsFull: Bool { self != .phone }

    /// How far across the bottom bar's buttons may sit: SheetHost's 540 pt on a wide screen, the whole width elsewhere.
    public var barBand: CGFloat { self == .wide ? Self.contentCap : .infinity }

    /// The tab row's side insets: on a wide screen the row is laid out as on the widest iPhone, in the middle; elsewhere
    /// the screen's own (`MobileSideInsets`).
    public func carouselInsets(size: CGSize, insets: (left: CGFloat, right: CGFloat)) -> (left: CGFloat, right: CGFloat) {
        guard self == .wide else { return insets }
        let extra = max(0, (size.width - insets.left - insets.right - Self.phoneWidth) / 2)
        return (insets.left + extra, insets.right + extra)
    }
}
