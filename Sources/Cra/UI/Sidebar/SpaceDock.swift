import AppKit
import SwiftUI

/// Arc's Library glyph: a filled box with a small confetti puff (cloud, dot, triangle) rising
/// from it. Drawn once per theme brightness into an image for the dock's Library button.
struct LibraryGlyph: View {
    let dark: Bool

    var body: some View {
        let ink = dark ? Color.white.opacity(0.55) : Color.black.opacity(0.26)
        ZStack(alignment: .top) {
            // Arc's box has no lid line: a 13×10 rounded box with a light slot near the top.
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .frame(width: 14, height: 11)
                .overlay(alignment: .top) {
                    Capsule().fill(dark ? Color.black.opacity(0.5) : Color.white.opacity(0.7))
                        .frame(width: 5, height: 1.6).padding(.top, 2.4)
                }
                .offset(y: 8)
            HStack(alignment: .bottom, spacing: 1) {
                Image(systemName: "cloud.fill").font(.system(size: 7, weight: .bold))
                Circle().frame(width: 2, height: 2).offset(y: -4)
                Image(systemName: "triangle.fill").font(.system(size: 4, weight: .bold)).offset(y: -1)
            }
            .offset(x: 2, y: -1)
        }
        // The stack is laid out by the box alone (11 pt), so the puff above it left the glyph
        // 3.5 pt low, its box on the button's bottom edge (GitHub #11). Centre puff + box.
        .offset(y: -3.5)
        .foregroundStyle(ink)
        .frame(width: 28, height: 28)
    }

    @MainActor private static var cache: [Bool: NSImage] = [:]

    @MainActor static func image(dark: Bool) -> NSImage? {
        if let img = cache[dark] { return img }
        let r = ImageRenderer(content: LibraryGlyph(dark: dark))
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage
        cache[dark] = img
        return img
    }
}
