import AppKit

/// Copy as Image (LinkSummaryShareImage) against Arc 1.171's own copy of a Google result's card
/// (10 Nov 2026, a 912 × 1289 px TIFF): 304 pt at 3x, the picture inset 2 pt, a white card, the
/// dashed #CFD0FB line starting with a 3 pt gap, and a #F6F6FF footer.
@main
enum LinkSummaryShareImageTests {
    private static var checks = 0

    static func expect(_ ok: Bool, _ message: String) {
        checks += 1
        if !ok { FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!); exit(1) }
    }

    static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> UInt32 {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        return UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8 | UInt32((c.blueComponent * 255).rounded())
    }

    static func near(_ a: UInt32, _ b: UInt32, _ tolerance: Int = 6) -> Bool {
        [16, 8, 0].allSatisfy { abs(Int(a >> UInt32($0) & 0xff) - Int(b >> UInt32($0) & 0xff)) <= tolerance }
    }

    @MainActor
    static func main() {
        _ = NSApplication.shared
        let result = LinkSummaryResult(url: "https://www.youtube.com/watch?v=0tR7dlqDu3E", title: "T", host: "youtube.com",
            quickSummary: "Best paper airplane for distance.", details: [
            .init(label: "Record Holder", icon: "trophy", info: "2026 world record for distance."),
            .init(label: "Video Link", icon: "video", info: "Watch on YouTube for instructions."),
            .init(label: "Technique", icon: "pencil", info: "Learn folding techniques for optimal flight."),
            .init(label: "Materials", icon: "paperplane", info: "Use lightweight paper for best results."),
        ])
        // A 1200 × 630 share picture in one colour, as og:images usually are sized.
        let banner = NSImage(size: NSSize(width: 1200, height: 630), flipped: false) { r in
            NSColor(srgbRed: 0.1, green: 0.2, blue: 0.6, alpha: 1).setFill(); r.fill(); return true
        }
        let image = LinkSummaryShareImage.render(result, image: banner, favicon: nil)
        guard let rep = image.representations.first as? NSBitmapImageRep else { expect(false, "the copy is a bitmap"); return }
        expect(rep.pixelsWide == 912, "the copy is 304 pt wide at 3x, as Arc's (got \(rep.pixelsWide) px)")
        expect(abs(rep.pixelsHigh - 1289) <= 6, "the copy is about as tall as Arc's 1289 px for the same card (got \(rep.pixelsHigh))")
        expect(image.size.width == 304, "the image's point size is 304 wide")
        expect(near(pixel(rep, 456, 2), 0xFFFFFF), "a white 2 pt border above the picture")
        expect(near(pixel(rep, 456, 200), 0x1A3399, 12), "the picture fills the banner")
        expect(near(pixel(rep, 456, 500), 0xFFFFFF), "the card under the picture is white (picture 900 × 472 px, as Arc's)")
        expect(near(pixel(rep, 456, rep.pixelsHigh - 10), 0xF6F6FF), "the footer is #F6F6FF")

        // The dashed line: find the row, then its pattern from the left edge.
        guard let row = (900..<rep.pixelsHigh).first(where: { y in (0..<120).contains { near(pixel(rep, $0, y), 0xCFD0FB, 4) } }) else {
            expect(false, "a dashed line above the footer"); return
        }
        let pattern = (0..<60).map { near(pixel(rep, $0, row), 0xCFD0FB, 4) }
        expect(pattern.prefix(9).allSatisfy { !$0 }, "the dashes start with a 3 pt gap, as Arc's")
        expect(pattern[9..<21].allSatisfy { $0 }, "a dash is 4 pt (12 px)")
        expect(pattern[21..<39].allSatisfy { !$0 }, "the gap is 6 pt (18 px)")
        expect(abs(row - 1139) <= 4, "the dashed line sits where Arc's does for the same card (row \(row), Arc 1139)")

        // Without a picture the card starts with the summary, nothing above it.
        let plain = LinkSummaryShareImage.render(result, image: nil, favicon: nil)
        let plainRep = plain.representations.first as! NSBitmapImageRep
        expect(plainRep.pixelsHigh < rep.pixelsHigh - 400, "no picture, no banner (\(plainRep.pixelsHigh) px)")
        expect((0..<30).allSatisfy { near(pixel(plainRep, 456, $0), 0xFFFFFF) }, "no picture: white above the summary")

        // More rows make a taller copy; none cut off.
        var long = result
        long.details.append(.init(label: "Extra", icon: "star", info: "One more row of text that is long enough to wrap onto a second line."))
        let longRep = LinkSummaryShareImage.render(long, image: nil, favicon: nil).representations.first as! NSBitmapImageRep
        expect(longRep.pixelsHigh > plainRep.pixelsHigh + 100, "a fifth row makes the copy taller")
        print("Copy as Image: \(checks) checks passed")
    }
}
