import CraCore
import UIKit

extension UIImage {
    /// Whether the picture is a capture that came back black rather than a page
    /// (`MobileSnapshot.looksBlank`).
    var looksBlank: Bool {
        guard let rgb = averageRGB() else { return false }
        return MobileSnapshot.looksBlank(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    /// The average colour of the picture's top strip: the band a tab shows while its page has not
    /// painted a theme of its own.
    func topBandColor(share: CGFloat = 0.05) -> UIColor? {
        averageRGB(topShare: share).map { UIColor(red: $0.r, green: $0.g, blue: $0.b, alpha: 1) }
    }

    /// The average colour of the picture, or of its top `topShare` of rows. Drawn small first, an
    /// 8 × 8 grid, so a full-screen picture costs next to nothing and no single pixel decides it.
    private func averageRGB(topShare: CGFloat = 1) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard var image = cgImage, image.width > 0, image.height > 0 else { return nil }
        if topShare < 1 {
            let rows = max(1, Int(CGFloat(image.height) * topShare))
            guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: rows)) else { return nil }
            image = top
        }
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sum = (r: 0, g: 0, b: 0)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            sum.r += Int(pixels[index]); sum.g += Int(pixels[index + 1]); sum.b += Int(pixels[index + 2])
        }
        let count = CGFloat(side * side) * 255
        return (CGFloat(sum.r) / count, CGFloat(sum.g) / count, CGFloat(sum.b) / count)
    }
}
