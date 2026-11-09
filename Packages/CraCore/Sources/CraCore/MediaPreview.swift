import CoreGraphics
import Foundation

/// Arc's preview for a picture or video picked in Library ▸ Media (BaseHomeComponents'
/// MediaPreviewWindow, Arc 1.172.1, Victor's Arc, 8 Nov 2026): a panel over the dimmed window, the
/// Library left as it was. A 1728 × 1084 pt window gave a 1330 × 817 pt panel, 199 pt in from each
/// side and 133 pt from the top and bottom. Its 46 pt header holds ✕, ‹ ›, the file's name and age,
/// then ⋯ and "Open in Preview ↗"; the picture fits 15 pt inside the rest, over a blurred copy of
/// itself. It grows out of the picked thumbnail in about 0.21 s, easing out with a long settle.
public enum MediaPreview {
    public static let sideInset: CGFloat = 199.0 / 1728
    public static let topInset: CGFloat = 133.0 / 1084
    public static let headerHeight: CGFloat = 46
    public static let mediaInset: CGFloat = 15
    public static let cornerRadius: CGFloat = 16
    public static let openDuration: TimeInterval = 0.21
    public static let closeDuration: TimeInterval = 0.16
    /// Ease-out with a long, soft landing (the panel's last 10 % takes half the time).
    public static let curve: (Float, Float, Float, Float) = (0.2, 0.75, 0.25, 1)

    /// The panel in a window's content (points, origin at the bottom left).
    public static func panel(in bounds: CGRect) -> CGRect {
        let dx = (bounds.width * sideInset).rounded(), dy = (bounds.height * topInset).rounded()
        return bounds.insetBy(dx: dx, dy: dy)
    }

    /// Where the picture goes in the panel (bottom-left origin): fitted inside, centred.
    public static func media(_ size: CGSize, in panel: CGRect) -> CGRect {
        let box = CGRect(x: panel.minX + mediaInset, y: panel.minY + mediaInset,
                         width: panel.width - 2 * mediaInset, height: panel.height - headerHeight - 2 * mediaInset)
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = (size.width * scale).rounded(), h = (size.height * scale).rounded()
        return CGRect(x: (box.midX - w / 2).rounded(), y: (box.midY - h / 2).rounded(), width: w, height: h)
    }

    /// ‹ and › step through the grid's order and stop at its ends.
    public static func step(_ index: Int, by delta: Int, count: Int) -> Int? {
        let next = index + delta
        return (0..<count).contains(next) ? next : nil
    }

    /// The header's age ("1 day ago", "5 minutes ago").
    public static func age(_ date: Date, now: Date, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return f.localizedString(for: min(date, now), relativeTo: now)
    }
}
