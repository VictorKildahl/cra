import CraCore
import SwiftUI

extension MobileAppIcon {
    // Xcode exports the Icon Composer previews as bundle files. Other previews are catalog images.
    private static let nativePreviews: [Self: UIImage] = allCases.reduce(into: [:]) { images, icon in
        if let url = Bundle.main.url(forResource: icon.previewName, withExtension: "png") {
            images[icon] = UIImage(contentsOfFile: url.path)
        }
    }

    var previewImage: Image {
        if let image = Self.nativePreviews[self] { return Image(uiImage: image) }
        return Image(previewName)
    }
}

/// App Settings ▸ Change App Icon: Arc Search's bottom sheet, from 60fps.design's "App Icon Dock
/// Picker" clip. "App Icon" over a row of icons standing on a glass shelf that scrolls sideways;
/// the current one sits a little larger and higher with a blue dot under it. Picking one changes
/// the icon, and iOS says so in its own alert. Sizes from the clip (about 2 px per point there):
/// 78 pt icons 110 pt apart, a 41 pt shelf with a 17 pt front edge.
struct AppIconDock: View {
    var done: () -> Void = {}
    @State private var selected = MobileAppIcon(alternateName: UIApplication.shared.alternateIconName)
    /// Center the row when it fits. Narrower sheets scroll from the left edge as in Arc Search.
    @State private var width: CGFloat = 0

    private static let icon: CGFloat = 78
    private static let gap: CGFloat = 32
    private static let shelfTop: CGFloat = 41
    private static let shelfFront: CGFloat = 17
    private static let dot = Color(red: 0x2b / 255, green: 0x3a / 255, blue: 0xf0 / 255)
    /// The icons and their 24 pt margins, without the shelf that runs past both ends.
    private static var rowWidth: CGFloat {
        let count = CGFloat(MobileAppIcon.allCases.count)
        return count * icon + (count - 1) * gap + 48
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("App Icon").font(.system(size: 17, weight: .semibold))
                HStack {
                    Spacer()
                    Button(action: done) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 30, height: 30).background(Color(white: 0.9), in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 18).padding(.top, 18)
            Spacer(minLength: 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.gap) {
                    ForEach(MobileAppIcon.allCases) { icon in iconView(icon) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, Self.shelfFront + Self.shelfTop * 0.45)
                // Behind the row, so the shelf running past both ends doesn't count toward what scrolls:
                // the row stops at its last icon instead of 430 pt of empty shelf.
                .background(alignment: .bottomLeading) { shelf }
                .frame(width: fits ? Self.rowWidth : nil, alignment: .leading)
                .frame(width: fits ? width : nil)
            }
            .scrollClipDisabled()
            .scrollDisabled(fits)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            Spacer(minLength: 30)
        }
        .background(LinearGradient(colors: [Color(white: 0.965), Color(red: 0.95, green: 0.94, blue: 0.99)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }

    private var fits: Bool { width >= Self.rowWidth }

    /// The glass shelf the icons stand on: a pale top face with their reflections, a white front edge.
    private var shelf: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: Self.gap) {
                    ForEach(MobileAppIcon.allCases) { icon in
                        icon.previewImage.resizable().frame(width: Self.icon, height: Self.icon)
                            .clipShape(RoundedRectangle(cornerRadius: Self.icon * 0.225, style: .continuous))
                            .scaleEffect(x: 1, y: -1)
                            .opacity(0.13).blur(radius: 1.5)
                    }
                }
                // The shelf reaches 200 pt past each end; its reflections line up with the icons.
                .padding(.leading, 24 + 200)
                .offset(y: Self.shelfTop * 0.55)
            }
            .frame(height: Self.shelfTop)
            .clipped()
            Rectangle().fill(Color.white.opacity(0.95)).frame(height: Self.shelfFront)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 8)
        }
        .frame(width: CGFloat(MobileAppIcon.allCases.count) * (Self.icon + Self.gap) + 48 + 400)
        .offset(x: -200)
    }

    private func iconView(_ icon: MobileAppIcon) -> some View {
        let isSelected = icon == selected
        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selected = icon }
            AppIconPicker.apply(icon)
        } label: {
            icon.previewImage.resizable().frame(width: Self.icon, height: Self.icon)
                .clipShape(RoundedRectangle(cornerRadius: Self.icon * 0.225, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                .scaleEffect(isSelected ? 1.08 : 1)
                .offset(y: isSelected ? -4 : 0)
                .overlay(alignment: .bottom) {
                    Capsule().fill(Self.dot).frame(width: 14, height: 5).offset(y: 16).opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.label)
        .accessibilityIdentifier("icon-\(icon.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
