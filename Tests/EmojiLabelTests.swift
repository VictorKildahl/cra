import AppKit

/// A space's emoji label in the dock and the space header, drawn off screen the way macOS 27 draws
/// it: clipped to its frame, and with the cell's text cut at the baseline (GitHub #399).
@main
enum EmojiLabelTests {
    private static var checks = 0

    /// Where each view puts its label: the dock's 34 × 32 pt cell (`SpaceCellView`, not flipped,
    /// 13 pt, centred) and the 36 pt space header (`SpaceHeaderView`, flipped, 14 pt, 1.25 pt above centre).
    private struct Place {
        let name: String, size: CGFloat, holder: CGSize, flipped: Bool
        let y: (_ holderHeight: CGFloat, _ labelHeight: CGFloat) -> CGFloat
    }
    private static let places = [
        Place(name: "dock", size: 13, holder: CGSize(width: 34, height: 32), flipped: false) { ($0 - $1) / 2 },
        Place(name: "header", size: 14, holder: CGSize(width: 40, height: 36), flipped: true) { ($0 - $1) / 2 - 1.25 },
    ]

    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        wholeEmojiWhenClipped()
        wholeEmojiWhenCellCutsAtBaseline()
        sameLookAsStockLabel()
        textUnchanged()
        print("Emoji label: \(checks) checks passed")
    }

    // promise: #399
    /// Apple Color Emoji reaches below the system font's line. Clipped to its frame, as on the
    /// reporter's macOS 27.2, the label still shows every pixel macOS 26 drew unclipped, in the same
    /// place, in the dock and the space header (#399).
    @MainActor
    private static func wholeEmojiWhenClipped() {
        for place in places {
            for emoji in ["🏠", "🌱", "💼", "😀", "🇩🇰", "👨‍💻", "🐙"] {
                for scale: CGFloat in [1, 2] {
                    let (holder, label) = make(emoji, in: place)
                    let h = label.intrinsicContentSize.height
                    let laidOut = NSRect(x: 0, y: place.y(place.holder.height, h), width: place.holder.width, height: h)
                    let unclipped = pixels(holder, label, frame: laidOut, clips: false, scale: scale)
                    let fitted = label.frameHoldingInk(laidOut)
                    let top = place.flipped ? \NSRect.minY : \NSRect.maxY
                    expect(fitted[keyPath: top] == laidOut[keyPath: top] && fitted.minX == laidOut.minX
                           && fitted.width == laidOut.width && fitted.height > laidOut.height,
                           "\(place.name) \(emoji) grows down only, so it doesn't move")
                    // Rows from the laid-out top edge down: the top edge stays where Arc's measurements put
                    // it (the header's, 8.25 pt, cuts a quarter pixel of antialiasing either way).
                    let topRow = Int(((place.flipped ? laidOut.minY : place.holder.height - laidOut.maxY) * scale).rounded(.up))
                    let rowBytes = Int(place.holder.width * scale) * 4
                    let clipped = pixels(holder, label, frame: fitted, clips: true, scale: scale)
                    expect(clipped[(topRow * rowBytes)...] == unclipped[(topRow * rowBytes)...],
                           "\(place.name) \(emoji) at \(Int(scale))x, clipped to its frame, keeps its bottom row")
                }
            }
        }
    }

    // promise: #399
    /// The reporter's macOS 27.2 cut every dock emoji flat near the baseline, in 0.1.41 and again
    /// in 0.1.42 with the frame grown to hold the picture: the cut is in the cell's text drawing,
    /// not at the view's edge. Modelled by a cell that loses everything under the baseline (it
    /// reproduces the cut on a plain sidebar label), `EmojiLabel` still draws the emoji's every
    /// pixel, where the plain label draws it unclipped, at 1x and 2x, in the dock and the header.
    @MainActor
    private static func wholeEmojiWhenCellCutsAtBaseline() {
        for place in places {
            for emoji in ["🏠", "🎮", "🃏", "🇩🇰", "👨‍💻", "🐙"] {
                for scale: CGFloat in [1, 2] {
                    let (plainHolder, plain) = make(emoji, in: place)
                    let h = plain.intrinsicContentSize.height
                    let laidOut = NSRect(x: 0, y: place.y(place.holder.height, h), width: place.holder.width, height: h)
                    let reference = ink(pixels(plainHolder, plain, frame: laidOut, clips: false, scale: scale))

                    let (cutHolder, cut) = make(emoji, in: place, cell: BaselineCutCell.self)
                    let cutInk = ink(pixels(cutHolder, cut, frame: cut.frameHoldingInk(laidOut), clips: true, scale: scale))
                    // Pixel rows from the holder's top down to the baseline; a flag at 1x has no ink under it.
                    let fromTop = place.flipped ? laidOut.minY : place.holder.height - laidOut.maxY
                    let baselineRow = Int(((fromTop + plain.firstBaselineOffsetFromTop) * scale).rounded(.down))
                    let width = Int(place.holder.width * scale)
                    if reference[(baselineRow * width)...].contains(true) {
                        expect(cutInk != reference && cutInk.filter { $0 }.count < reference.filter { $0 }.count,
                               "\(place.name) \(emoji) at \(Int(scale))x: the model cuts a plain label, as macOS 27.2 did")
                    }

                    let (holder, label) = make(emoji, in: place, cell: BaselineCutCell.self, type: EmojiLabel.self)
                    let drawn = ink(pixels(holder, label, frame: label.frameHoldingInk(laidOut), clips: true, scale: scale))
                    // From the laid-out top edge down, as above: the header's 8.25 pt top cuts a quarter pixel either way.
                    let topRow = Int((fromTop * scale).rounded(.up)) * width
                    expect(drawn[topRow...] == reference[topRow...], "\(place.name) \(emoji) at \(Int(scale))x: EmojiLabel keeps every pixel, in place")
                }
            }
        }
    }

    /// Unclipped, `EmojiLabel` draws the very pixels a stock sidebar label does, edges included, so
    /// the dock and header look as they shipped (their snapshots in Tests/Snapshots).
    @MainActor
    private static func sameLookAsStockLabel() {
        for place in places {
            for emoji in ["🏠", "🌱", "💼", "🇩🇰", "👨‍💻", "A"] {
                for scale: CGFloat in [1, 2] {
                    let (plainHolder, plain) = make(emoji, in: place)
                    let h = plain.intrinsicContentSize.height
                    let laidOut = NSRect(x: 0, y: place.y(place.holder.height, h), width: place.holder.width, height: h)
                    let stock = pixels(plainHolder, plain, frame: laidOut, clips: false, scale: scale)
                    let (holder, label) = make(emoji, in: place, type: EmojiLabel.self)
                    expect(pixels(holder, label, frame: laidOut, clips: false, scale: scale) == stock,
                           "\(place.name) \(emoji) at \(Int(scale))x looks as a stock label draws it")
                }
            }
        }
    }

    /// Which pixels the drawing covers: the model's cut cell draws through `drawInterior`, once, so
    /// its edges are fainter than a stock label's; where the ink is is what counts.
    private static func ink(_ bytes: [UInt8]) -> [Bool] {
        stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] > 0 }
    }

    /// A text cell that draws nothing under its first baseline: what the reporter's macOS 27.2 did
    /// to a label's emoji whatever the label's frame.
    private final class BaselineCutCell: NSTextFieldCell {
        override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
            let baseline = (controlView as? NSTextField)?.firstBaselineOffsetFromTop ?? cellFrame.height
            NSGraphicsContext.saveGraphicsState()
            let top = controlView.isFlipped ? cellFrame.minY : cellFrame.maxY - baseline
            NSRect(x: cellFrame.minX, y: top, width: cellFrame.width, height: baseline).clip()
            super.drawInterior(withFrame: cellFrame, in: controlView)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Plain text already fits its line, so its frame stays as laid out.
    @MainActor
    private static func textUnchanged() {
        for place in places {
            for text in ["", "Work", "gyp"] {
                let (_, label) = make(text, in: place)
                let frame = NSRect(x: 2, y: 6, width: 40, height: label.intrinsicContentSize.height)
                expect(label.frameHoldingInk(frame) == frame, "\(place.name) \"\(text)\" keeps its frame")
            }
        }
    }

    /// The views' label: `NSTextField.sidebarLabel`'s setup, centred, in a layer-backed holder. `cell`
    /// stands in for the system's text cell; `type` is the label class.
    @MainActor
    private static func make(_ text: String, in place: Place, cell: NSTextFieldCell.Type? = nil,
                             type: NSTextField.Type = NSTextField.self) -> (NSView, NSTextField) {
        let l = type == EmojiLabel.self ? EmojiLabel(labelWithString: text) : NSTextField(labelWithString: text)
        if let cell {
            l.cell = cell.init(textCell: text)
            l.isEditable = false
            l.isSelectable = false
            l.isBordered = false
            l.drawsBackground = false
            l.textColor = .labelColor
        }
        l.font = .systemFont(ofSize: place.size)
        l.lineBreakMode = .byTruncatingTail
        l.usesSingleLineMode = true
        l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true
        l.alignment = .center
        let holder = place.flipped ? FlippedView() : NSView()
        holder.frame = NSRect(origin: .zero, size: place.holder)
        holder.wantsLayer = true
        holder.addSubview(l)
        return (holder, l)
    }

    @MainActor
    private static func pixels(_ holder: NSView, _ label: NSTextField, frame: NSRect, clips: Bool, scale: CGFloat) -> [UInt8] {
        label.frame = frame
        label.clipsToBounds = clips
        let w = Int(holder.bounds.width * scale), h = Int(holder.bounds.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: w * 4, bitsPerPixel: 32)!
        rep.size = holder.bounds.size
        holder.cacheDisplay(in: holder.bounds, to: rep)
        let bytes = Array(UnsafeBufferPointer(start: rep.bitmapData!, count: w * h * 4))
        expect(stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }, "\(label.stringValue) drew something")
        return bytes
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
