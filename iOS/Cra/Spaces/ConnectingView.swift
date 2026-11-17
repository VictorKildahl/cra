import CraCore
import SwiftUI

/// Arc Search 1.49's Spaces sheet while the desktop's Spaces are fetched (Victor's screenshot
/// IMG_1897): the sync glow on pale blue, an outlined cloud with two waves over its left
/// shoulder, and "Connecting". Positions are from the 440 pt screen, relative to the sheet's middle.
struct ConnectingView: View {
    static let iconBlue = Color(red: 0x31 / 255, green: 0x39 / 255, blue: 0xFB / 255)
    static let textBlue = Color(red: 0x2F / 255, green: 0x39 / 255, blue: 0xFF / 255)

    var body: some View {
        GeometryReader { geometry in
            let middle = geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                SyncGlow(background: SyncGlow.connectingBackground)
                CloudWaves()
                    .stroke(Self.iconBlue, style: StrokeStyle(lineWidth: 9.7, lineCap: .round, lineJoin: .round))
                    .frame(width: CloudWaves.size.width, height: CloudWaves.size.height)
                    .position(x: geometry.size.width / 2 - 100 + CloudWaves.size.width / 2, y: middle - 139 + CloudWaves.size.height / 2)
                Text(MobileSyncIntro.connecting)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Self.textBlue)
                    .fixedSize()
                    .position(x: geometry.size.width / 2, y: middle + 84)
                    .accessibilityIdentifier("spaces-connecting")
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .environment(\.colorScheme, .light)
    }
}

/// The cloud and waves, as stroke centre lines in a 190 × 175 box whose top left sits 100 pt
/// left of the screen's middle: three circles make the cloud (left lobe, crown, right lobe) over
/// a flat bottom; two arcs about one centre make the waves.
struct CloudWaves: Shape {
    static let size = CGSize(width: 190, height: 175)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottom: CGFloat = 162.4
        let left = (center: CGPoint(x: 58, y: 140), radius: CGFloat(22.4))
        let crown = (center: CGPoint(x: 93, y: 116.5), radius: CGFloat(40.7))
        let right = (center: CGPoint(x: 138, y: 129.4), radius: CGFloat(33))
        path.move(to: CGPoint(x: left.center.x, y: bottom))
        path.addArc(center: left.center, radius: left.radius, startAngle: .degrees(90), endAngle: .degrees(255.4), clockwise: false)
        path.addArc(center: crown.center, radius: crown.radius, startAngle: .degrees(177.4), endAngle: .degrees(332.4), clockwise: false)
        path.addArc(center: right.center, radius: right.radius, startAngle: .degrees(254.3), endAngle: .degrees(450), clockwise: false)
        path.closeSubpath()
        let waves = CGPoint(x: 80, y: 80)
        path.move(to: point(waves, 71.7, 200))
        path.addArc(center: waves, radius: 71.7, startAngle: .degrees(200), endAngle: .degrees(262), clockwise: false)
        path.move(to: point(waves, 42, 203))
        path.addArc(center: waves, radius: 42, startAngle: .degrees(203), endAngle: .degrees(260), clockwise: false)
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
}
