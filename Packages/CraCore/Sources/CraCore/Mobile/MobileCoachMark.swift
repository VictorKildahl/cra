import CoreGraphics

/// Arc Search 1.49's first-run coach mark over the search sheet (Victor's recording, 1:21):
/// "Tap *Browse for Me* / for a faster answer" above the field, and a thin purple-to-pink line
/// that leaves the text, runs right and turns down onto the first question's Browse for Me chip.
public enum MobileCoachMark {
    public static let title = (before: "Tap ", emphasis: "Browse for Me", after: "for a faster answer")

    /// Shown while the starter questions are and Browse for Me can be picked.
    public static func shows(startersShown: Bool, offersBrowseForMe: Bool) -> Bool {
        startersShown && offersBrowseForMe
    }

    /// Measured on the recording (440 pt wide): the text's two lines centred 24 pt apart, the
    /// second 95 pt above the sheet's field; the line starts 18 pt under the text.
    public static let lineSpacing: CGFloat = 24
    public static let textAboveField: CGFloat = 95
    public static let lineStartGap: CGFloat = 18
    /// The line's level stretch is this far under its start, it turns over 26 pt, and its point
    /// stops 6 pt above the chip.
    public static let bendDrop: CGFloat = 47
    public static let turnRadius: CGFloat = 26
    public static let tipGap: CGFloat = 6
    public static let lineWidth: CGFloat = 2
    public static let arrowHead: CGFloat = 7
    /// Its ends: #7b55ff into #ff2d9b.
    public static let lineStart: UInt32 = 0x7b55ff
    public static let lineEnd: UInt32 = 0xff2d9b

    /// The line's corners: from under the text down and round to the right, along, then round
    /// and down to just above the chip. A chip left of the start (a narrow screen) mirrors it.
    public static func path(from start: CGPoint, toChipTop chip: CGPoint) -> (start: CGPoint, firstTurn: CGPoint, secondTurn: CGPoint, end: CGPoint) {
        let level = start.y + bendDrop
        let end = CGPoint(x: chip.x, y: chip.y - tipGap)
        return (start, CGPoint(x: start.x, y: level), CGPoint(x: end.x, y: level), end)
    }
}
