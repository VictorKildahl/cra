import CoreGraphics

/// Copy as Image remains 3x, with at most 16 MB of RGBA pixel storage.
public struct LinkSummaryShareBitmap {
    public static let scale: CGFloat = 3
    public static let maximumPixels = 4_000_000
    public let width: Int
    public let height: Int

    public init?(pointSize: CGSize) {
        let w = pointSize.width * Self.scale
        let h = pointSize.height * Self.scale
        guard w.isFinite, h.isFinite, w >= 1, h >= 1,
              w <= CGFloat(Self.maximumPixels), h <= CGFloat(Self.maximumPixels) else { return nil }
        let width = Int(w), height = Int(h)
        guard height <= Self.maximumPixels / width else { return nil }
        self.width = width
        self.height = height
    }
}
