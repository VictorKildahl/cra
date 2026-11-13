import SwiftUI

/// Arc Search's "Bring Arc to your home screen" walkthrough, from 60fps.design's "Add Widget"
/// clip: the widget with Add Widget and Maybe Later, then "Start by holding anywhere on your home
/// screen" and "Tap Edit and select Add Widget", each with a drawn home screen that acts it out.
/// Colours measured there: titles #2400a8, buttons #252dff, the sheet white to #fef2fa.
/// Arc Search's way into it was not seen; Cra's is App Settings ▸ Add Widget.
struct WidgetGuideView: View {
    var done: () -> Void = {}
    @State private var step = 0

    private static let ink = Color(red: 0x24 / 255, green: 0x00 / 255, blue: 0xa8 / 255)
    private static let button = Color(red: 0x25 / 255, green: 0x2d / 255, blue: 0xff / 255)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: done) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30).background(Color(white: 0.92), in: Circle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("widget-guide-close")
            }
            .padding(.horizontal, 20).padding(.top, 14)
            title.padding(.top, 36).padding(.horizontal, 28)
            Spacer(minLength: 20)
            Group {
                switch step {
                case 0: WidgetPreviewCard().frame(width: 150, height: 150).rotation3DEffect(.degrees(8), axis: (x: 0.4, y: -1, z: 0))
                        .shadow(color: .black.opacity(0.18), radius: 22, y: 14)
                case 1: HomeScreenDrawing(act: .hold)
                default: HomeScreenDrawing(act: .addWidget)
                }
            }
            .transition(.opacity)
            Spacer(minLength: 20)
            Button(action: next) {
                Text(step == 0 ? "Add Widget" : step == 1 ? "Next" : "Done!")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Self.button, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("widget-guide-next")
            .padding(.horizontal, 22)
            Button("Maybe Later", action: done)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Self.button)
                .padding(.top, 14).padding(.bottom, 8)
                .opacity(step == 0 ? 1 : 0)
                .disabled(step != 0)
        }
        .background(LinearGradient(colors: [Color(red: 0xfe / 255, green: 0xfd / 255, blue: 1), Color(red: 0xfe / 255, green: 0xf2 / 255, blue: 0xfa / 255)],
                                   startPoint: .center, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private func next() {
        guard step < 2 else { return done() }
        withAnimation(.easeInOut(duration: 0.3)) { step += 1 }
    }

    @ViewBuilder
    private var title: some View {
        let font = Font.system(size: 28, weight: .bold, design: .rounded)
        Group {
            switch step {
            case 0: Text("Bring Cra to your home screen")
            case 1: Text("Start by holding \(Text("anywhere").italic()) on your home screen")
            default: Text("Tap \(Image(systemName: "hand.point.up.left")) Edit and select \(Text("Add Widget").italic())")
            }
        }
        .font(font)
        .foregroundStyle(Self.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("widget-guide-title")
    }
}

/// The small widget as it looks on the home screen (CraWidgets' small family, drawn again here:
/// the app can't show the extension's views).
struct WidgetPreviewCard: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(red: 0x18 / 255, green: 0x00 / 255, blue: 0x8c / 255), location: 0),
                    .init(color: Color(red: 0x6a / 255, green: 0x2f / 255, blue: 0xa8 / 255), location: 0.38),
                    .init(color: Color(red: 0xc8 / 255, green: 0x43 / 255, blue: 0x96 / 255), location: 0.68),
                    .init(color: Color(red: 0xff / 255, green: 0x40 / 255, blue: 0x6c / 255), location: 1),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image("LaunchMark").resizable().scaledToFit().frame(width: side * 0.2).position(x: side * 0.2, y: side * 0.28)
                HStack {
                    Text("Search").font(.system(size: side * 0.1)).foregroundStyle(Color(white: 0.62))
                    Spacer(minLength: 0)
                }
                .padding(.leading, side * 0.11)
                .frame(width: side * 0.75, height: side * 0.26)
                .background(Color.white, in: Capsule())
                .position(x: side * 0.36 + side * 0.375, y: side * 0.27)
                HStack(spacing: side * 0.07) {
                    ForEach(["mic.fill", "desktopcomputer"], id: \.self) { symbol in
                        Image(systemName: symbol).font(.system(size: side * 0.08, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                            .frame(width: side * 0.35, height: side * 0.22).background(Color.black.opacity(0.16), in: Capsule())
                    }
                }
                .position(x: side * 0.5, y: side * 0.77)
            }
            .clipShape(RoundedRectangle(cornerRadius: side * 0.15, style: .continuous))
        }
        .accessibilityElement()
        .accessibilityLabel("Cra widget")
    }
}

/// A drawn home screen that acts out a step on a loop: a touch held down until the icons jiggle,
/// or the touch on the + button, Add Widget, and the gallery with Cra's widget in it.
struct HomeScreenDrawing: View {
    enum Act { case hold, addWidget }
    let act: Act

    private static let screen = Color(red: 0xdd / 255, green: 0xdf / 255, blue: 0xfe / 255)
    private static let tile = Color(red: 0xc9 / 255, green: 0xc8 / 255, blue: 0xf0 / 255)
    private static let badge = Color(red: 0x9f / 255, green: 0x9f / 255, blue: 0xd1 / 255)
    private static let touch = Color(red: 0x5a / 255, green: 0x5c / 255, blue: 0xf6 / 255)

    var body: some View {
        TimelineView(.animation) { context in
            let period = act == .hold ? 2.6 : 4.2
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
            canvas(t: t)
        }
        .frame(width: 230, height: 330)
        .accessibilityHidden(true)
    }

    private func canvas(t: Double) -> some View {
        let editing = act == .addWidget || t > 1.1
        let jiggle = editing ? sin(t * 40) * 1.6 : 0
        let menuShown = act == .addWidget && t > 1.2 && t < 2.3
        let galleryShown = act == .addWidget && t >= 2.3
        let touchPoint: CGPoint = act == .hold ? CGPoint(x: 160, y: 200) : (t < 1.0 ? CGPoint(x: 120, y: 160) : CGPoint(x: 36, y: 26))
        let touchOpacity = act == .hold ? (t < 1.6 ? 1.0 : 0) : (galleryShown ? 0 : 1)
        let touchScale = act == .hold ? (t < 0.3 ? 1.3 : 1.0) : (t > 0.9 && t < 1.2 ? 0.85 : 1.0)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Self.screen, Self.screen.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            if editing {
                Capsule().fill(Self.touch).frame(width: 34, height: 18).overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                    .position(x: 36, y: 26)
                Capsule().fill(Self.badge.opacity(0.7)).frame(width: 52, height: 18).position(x: 92, y: 26)
            } else {
                Capsule().fill(Self.badge.opacity(0.7)).frame(width: 56, height: 16).position(x: 115, y: 26)
            }
            ForEach(0..<10, id: \.self) { index in
                let column = index % 4, row = index / 4
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Self.tile)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topLeading) {
                        if editing { Circle().fill(Self.badge).frame(width: 11, height: 11).overlay(Rectangle().fill(.white).frame(width: 5, height: 1.5)).offset(x: -4, y: -4) }
                    }
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? jiggle : -jiggle))
                    .position(x: 34 + CGFloat(column) * 54, y: 70 + CGFloat(row) * 54)
            }
            if menuShown {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(Self.tile).frame(width: 70, height: 8)
                    RoundedRectangle(cornerRadius: 3).fill(Self.badge.opacity(0.6)).frame(width: 52, height: 6)
                }
                .padding(12)
                .frame(width: 120, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .position(x: 76, y: 66)
            }
            if galleryShown {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8).frame(height: 20).background(Color(white: 0.93), in: Capsule())
                    HStack(spacing: 10) {
                        WidgetPreviewCard().frame(width: 92, height: 92)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.95)).frame(width: 92, height: 92)
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.96)).frame(width: 92, height: 70) }
                    }
                }
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .position(x: 115, y: 210)
                .transition(.move(edge: .bottom))
            }
            Circle().fill(Self.touch.opacity(0.85)).frame(width: 30, height: 30)
                .scaleEffect(touchScale)
                .position(touchPoint)
                .opacity(touchOpacity)
                .animation(.easeInOut(duration: 0.35), value: touchPoint)
        }
        .animation(.easeInOut(duration: 0.3), value: galleryShown)
        .animation(.easeInOut(duration: 0.2), value: menuShown)
    }
}
