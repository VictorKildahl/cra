import CraCore
import UIKit

/// Arc Search 1.49's coach mark (`MobileCoachMark`): two centred lines of white text above the
/// search field and a purple-to-pink line onto the first question's Browse for Me chip. It
/// takes no touches.
final class CoachMarkView: UIView {
    private let label = UILabel()
    private let gradient = CAGradientLayer()
    private let line = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        label.numberOfLines = 2
        label.textAlignment = .center
        label.attributedText = Self.text()
        label.isAccessibilityElement = true
        label.accessibilityLabel = MobileCoachMark.title.before + MobileCoachMark.title.emphasis + " " + MobileCoachMark.title.after
        label.accessibilityIdentifier = "coach-mark"
        addSubview(label)
        gradient.colors = [Palette.rgb(MobileCoachMark.lineStart).cgColor, Palette.rgb(MobileCoachMark.lineEnd).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        line.fillColor = UIColor.clear.cgColor
        line.strokeColor = UIColor.black.cgColor
        line.lineWidth = MobileCoachMark.lineWidth
        line.lineCap = .round
        line.lineJoin = .round
        gradient.mask = line
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func text() -> NSAttributedString {
        let size: CGFloat = 23
        let plain = UIFont.systemFont(ofSize: size, weight: .semibold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = MobileCoachMark.lineSpacing + 3
        style.maximumLineHeight = MobileCoachMark.lineSpacing + 3
        let attributes: [NSAttributedString.Key: Any] = [.font: plain, .foregroundColor: UIColor.white, .paragraphStyle: style]
        let text = NSMutableAttributedString(string: MobileCoachMark.title.before, attributes: attributes)
        var emphasis = attributes
        if let descriptor = UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold]) {
            emphasis[.font] = UIFont(descriptor: descriptor, size: size)
        }
        text.append(NSAttributedString(string: MobileCoachMark.title.emphasis, attributes: emphasis))
        text.append(NSAttributedString(string: "\n" + MobileCoachMark.title.after, attributes: attributes))
        return text
    }

    /// Lays the text above `field` and the line onto `chipTop`, both in this view.
    func place(field: CGRect, chipTop: CGPoint) {
        let height = 2 * (MobileCoachMark.lineSpacing + 3)
        let textBottom = field.minY - MobileCoachMark.textAboveField + MobileCoachMark.lineSpacing / 2 + 3
        label.frame = CGRect(x: 20, y: textBottom - height, width: bounds.width - 40, height: height)
        let start = CGPoint(x: bounds.midX, y: textBottom + MobileCoachMark.lineStartGap)
        let corners = MobileCoachMark.path(from: start, toChipTop: chipTop)
        let radius = min(MobileCoachMark.turnRadius, abs(corners.secondTurn.x - corners.firstTurn.x) / 2,
                         (corners.firstTurn.y - corners.start.y))
        let path = UIBezierPath()
        path.move(to: corners.start)
        path.addLine(to: CGPoint(x: corners.start.x, y: corners.firstTurn.y - radius))
        let direction: CGFloat = corners.secondTurn.x >= corners.firstTurn.x ? 1 : -1
        path.addQuadCurve(to: CGPoint(x: corners.firstTurn.x + direction * radius, y: corners.firstTurn.y), controlPoint: corners.firstTurn)
        path.addLine(to: CGPoint(x: corners.secondTurn.x - direction * radius, y: corners.secondTurn.y))
        path.addQuadCurve(to: CGPoint(x: corners.secondTurn.x, y: corners.secondTurn.y + radius), controlPoint: corners.secondTurn)
        path.addLine(to: corners.end)
        // The point: two short strokes back up from the end.
        let head = MobileCoachMark.arrowHead
        path.move(to: CGPoint(x: corners.end.x - head * 0.75, y: corners.end.y - head))
        path.addLine(to: corners.end)
        path.addLine(to: CGPoint(x: corners.end.x + head * 0.75, y: corners.end.y - head))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        line.frame = bounds
        line.path = path.cgPath
        CATransaction.commit()
    }
}

extension BrowserViewController {
    /// Puts the coach mark over the sheet while the sheet offers it, and fades it otherwise.
    func placeCoachMark() {
        coachMark.frame = view.bounds
        let target = isSearching && switcher == nil && !sheet.isHidden ? sheet.coachTarget : nil
        if let target {
            coachMark.place(field: sheet.convert(target.field, to: view), chipTop: sheet.convert(target.chipTop, to: view))
        }
        let alpha: CGFloat = target == nil ? 0 : 1
        guard coachMark.alpha != alpha else { return }
        UIView.animate(withDuration: 0.3) { self.coachMark.alpha = alpha }
    }
}
