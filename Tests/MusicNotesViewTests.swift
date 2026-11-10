import AppKit

/// The production note bitmaps composited over fixed backgrounds, without a window or CEF.
@main
enum MusicNotesViewTests {
    private static var checks = 0

    @MainActor
    static func main() {
        for shape in MusicNotes.Shape.allCases {
            for scale in [1, 2] {
                let light = pixels(shape, dark: false, scale: scale)
                expect((177...181).contains(Int(light.min()!)),
                       "light \(shape) at \(scale)x keeps the subtle 30% black tint on white")
                let dark = pixels(shape, dark: true, scale: scale)
                expect((202...206).contains(Int(dark.max()!)),
                       "dark \(shape) at \(scale)x keeps its 80% white tint")
            }
        }
        print("Music notes pixels: \(checks) checks passed")
    }

    @MainActor
    private static func pixels(_ shape: MusicNotes.Shape, dark: Bool, scale: Int) -> [UInt8] {
        let image = MusicNotesView.sprite(shape, dark: dark)!
        let width = image.width * scale, height = image.height * scale
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: dark ? 0 : 1, alpha: 1)
        context.fill(bounds)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
        return stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
