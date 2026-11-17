import SwiftUI
import UIKit

/// The grainy glow at the top of Arc Search 1.49's sync sheets ("Connecting", "Save links to Arc
/// from other apps!", "Sync with Arc Desktop"): blue-grey on the left, coral on the right, gone
/// 268 pt below the sheet's top. Colours and fall-off solved from Victor's screenshots IMG_1897
/// (on #E8F1FE) and IMG_1898 (on white), which show the same glow over two backgrounds.
struct SyncGlow: View {
    let background: Color

    static let connectingBackground = Color(red: 0xE8 / 255, green: 0xF1 / 255, blue: 0xFE / 255)

    private static let blue = Color(red: 0xA9 / 255, green: 0xB0 / 255, blue: 0xD1 / 255)
    private static let coral = Color(red: 0xFE / 255, green: 0x63 / 255, blue: 0x65 / 255)
    private static let height: CGFloat = 268

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 0) {
                ZStack {
                    Self.blue
                        .mask(LinearGradient(stops: [
                            .init(color: .black.opacity(0.55), location: 0), .init(color: .black, location: 0.18),
                            .init(color: .black.opacity(0.5), location: 0.34), .init(color: .clear, location: 0.5),
                        ], startPoint: .leading, endPoint: .trailing))
                        .mask(LinearGradient(stops: [
                            .init(color: .black.opacity(0.65), location: 0), .init(color: .black.opacity(0.57), location: 88 / Self.height),
                            .init(color: .black.opacity(0.31), location: 128 / Self.height), .init(color: .black.opacity(0.17), location: 168 / Self.height),
                            .init(color: .black.opacity(0.05), location: 238 / Self.height), .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                    Self.coral
                        .mask(LinearGradient(stops: [
                            .init(color: .clear, location: 0.23), .init(color: .black.opacity(0.88), location: 0.5),
                            .init(color: .black, location: 0.66), .init(color: .black, location: 1),
                        ], startPoint: .leading, endPoint: .trailing))
                        .mask(LinearGradient(stops: [
                            .init(color: .black.opacity(0.65), location: 0), .init(color: .black.opacity(0.55), location: 48 / Self.height),
                            .init(color: .black.opacity(0.5), location: 88 / Self.height), .init(color: .black.opacity(0.39), location: 128 / Self.height),
                            .init(color: .black.opacity(0.26), location: 168 / Self.height), .init(color: .black.opacity(0.18), location: 208 / Self.height),
                            .init(color: .black.opacity(0.1), location: 238 / Self.height), .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    Image(uiImage: Grain.image).resizable(resizingMode: .tile)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                }
                .frame(height: Self.height)
                Spacer(minLength: 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Film grain, drawn once: specks two pixels across (Arc's grain clumps at 2–3 px on a 3x
/// screen) of black and white at low alpha.
private enum Grain {
    static let image: UIImage = {
        let side = 96
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            var generator = SystemRandomNumberGenerator()
            let dot = 2 / format.scale
            var y: CGFloat = 0
            while y < CGFloat(side) {
                var x: CGFloat = 0
                while x < CGFloat(side) {
                    let value = Double.random(in: -1...1, using: &generator)
                    UIColor(white: value > 0 ? 1 : 0, alpha: abs(value) * 0.06).setFill()
                    context.fill(CGRect(x: x, y: y, width: dot, height: dot))
                    x += dot
                }
                y += dot
            }
        }
    }()
}
