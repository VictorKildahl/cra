import AppKit

extension NSImageView {
    private static let copyCheckName = "copyCheck"

    /// Arc's confirmation on a clicked Copy URL glyph (CraCore CopyCheck, GitHub #361): the link
    /// shrinks away, a checkmark in the glyph's ink draws itself in its place, holds, un-draws, and
    /// the link springs back. A second click starts it over. `glyphSize` is the link's point size.
    func playCopyCheck(glyphSize: CGFloat) {
        guard let layer, let host = superview?.layer, window != nil else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        host.sublayers?.filter { $0.name == Self.copyCheckName }.forEach { $0.removeFromSuperlayer() }
        layer.removeAnimation(forKey: Self.copyCheckName)

        let check = CAShapeLayer()
        check.name = Self.copyCheckName
        check.frame = layer.frame
        check.fillColor = nil
        check.strokeColor = (contentTintColor ?? .labelColor).cgColor
        check.lineWidth = CopyCheck.lineWidth(glyphSize: glyphSize)
        check.lineCap = .round
        check.lineJoin = .round
        check.contentsScale = window?.backingScaleFactor ?? 2
        check.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "strokeColor": NSNull()]
        host.insertSublayer(check, above: layer)
        // The points are y-down; the image is drawn centred in the view.
        let down: CGFloat = check.contentsAreFlipped() ? 1 : -1
        let mid = CGPoint(x: check.bounds.midX, y: check.bounds.midY)
        let path = CGMutablePath()
        for (i, p) in CopyCheck.points(glyphSize: glyphSize).enumerated() {
            let q = CGPoint(x: mid.x + p.x, y: mid.y + down * p.y)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        check.path = path
        check.opacity = 0
        check.strokeEnd = CopyCheck.checkOutEnd

        let end = CopyCheck.linkInStart + CopyCheck.linkInFadeDuration
        let checkIn = CopyCheck.checkInStart, hold = CopyCheck.holdUntil
        let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
        draw.values = [0, 0, 1, 1, CopyCheck.checkOutEnd]
        draw.keyTimes = Self.fractions([0, checkIn, checkIn + CopyCheck.checkDrawDuration, hold, hold + CopyCheck.checkUndrawDuration], of: end)
        draw.timingFunctions = [.init(name: .linear), .init(name: .easeOut), .init(name: .linear), .init(name: .easeInEaseOut)]
        draw.duration = end
        let shown = CAKeyframeAnimation(keyPath: "opacity")
        shown.values = [0, 0, 1, 1, 0]
        shown.keyTimes = Self.fractions([0, checkIn, checkIn + CopyCheck.checkFadeInDuration, CopyCheck.linkInStart, end], of: end)
        shown.timingFunctions = [.init(name: .linear), .init(name: .easeOut), .init(name: .linear), .init(name: .linear)]
        shown.duration = end
        let checkGroup = CAAnimationGroup()
        checkGroup.animations = reduce ? [shown] : [draw, shown]
        checkGroup.duration = end
        if reduce { check.strokeEnd = 1 }

        // The link: out with the check's arrival, back on a spring as it leaves (added to whatever
        // transform the glyph has, scaled about its centre).
        let c = CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x), y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
        func scaled(_ s: CGFloat) -> NSValue {
            var t = CATransform3DMakeTranslation(c.x, c.y, 0)
            t = CATransform3DScale(t, s, s, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(t, -c.x, -c.y, 0))
        }
        let out = CABasicAnimation(keyPath: "transform")
        out.isAdditive = true
        out.fromValue = scaled(1)
        out.toValue = scaled(CopyCheck.linkOutScale)
        out.duration = CopyCheck.linkOutDuration
        out.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let back = CASpringAnimation(keyPath: "transform")
        back.isAdditive = true
        back.stiffness = CopyCheck.springStiffness
        back.damping = CopyCheck.springDamping
        back.fromValue = scaled(CopyCheck.linkInScale)
        back.toValue = scaled(1)
        back.beginTime = CopyCheck.linkInStart
        back.duration = back.settlingDuration
        let gone = CAKeyframeAnimation(keyPath: "opacity")
        let total = CopyCheck.linkInStart + back.settlingDuration
        gone.values = [1, 0, 0, 1]
        gone.keyTimes = Self.fractions([0, CopyCheck.linkOutDuration, CopyCheck.linkInStart, end], of: total)
        gone.timingFunctions = [.init(name: .easeIn), .init(name: .linear), .init(name: .easeOut)]
        gone.duration = total
        let linkGroup = CAAnimationGroup()
        linkGroup.animations = reduce ? [gone] : [out, back, gone]
        linkGroup.duration = total

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak check] in check?.removeFromSuperlayer() }
        check.add(checkGroup, forKey: Self.copyCheckName)
        layer.add(linkGroup, forKey: Self.copyCheckName)
        CATransaction.commit()
    }

    private static func fractions(_ times: [TimeInterval], of total: TimeInterval) -> [NSNumber] {
        times.map { NSNumber(value: $0 / total) }
    }
}
