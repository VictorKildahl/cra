import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// General ▸ App Icon: the bundled icon, the alternates and the user's own image, a row of
/// tiles like Arc's App Icon pane (AppIconPreferencesContentView) in Cra's card idiom.
struct AppIconSection: View {
    private let icons = AppIconManager.shared
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
    }

    @ViewBuilder private var content: some View {
        SettingsHeader("App Icon")
        SettingsCard {
            HStack(alignment: .top, spacing: 0) {
                ForEach(AppIconManager.presets) { option in
                    AppIconTile(name: option.name, image: icons.image(for: option.id),
                                selected: icons.selectedID == option.id) { icons.select(option.id) }
                }
                AppIconTile(name: "Custom", image: icons.customImage, selected: icons.selectedID == AppIconManager.customID) {
                    if icons.customImage == nil { chooseImage() } else { icons.select(AppIconManager.customID) }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    use(url)
                    return true
                }
            }
            .padding(.horizontal, SettingsMetrics.cardRowInset)
            .padding(.vertical, 8)
            SettingsCardDivider()
            SettingsCardRow {
                Text("Your own icon").font(.system(size: 13))
            } trailing: {
                if icons.customImage != nil {
                    Button("Remove") { icons.removeCustom(); error = nil }
                }
                Button("Choose Image…") { chooseImage() }
            }
        }
        SettingsFootnote("Pick any image or drop one on Custom. It’s sized to match the other icons in the Dock, and a photo or a logo on a background fills the rounded tile. The Dock keeps the icon after Cra quits.")
        if let error { SettingsFootnote(error).foregroundStyle(.red) }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for Cra’s icon"
        panel.prompt = "Use as Icon"
        let done: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { use(url) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: done) } else { panel.begin(completionHandler: done) }
    }

    private func use(_ url: URL) {
        do {
            try icons.setCustom(from: url)
            error = nil
        } catch {
            self.error = "“\(url.lastPathComponent)” isn’t an image Cra can read."
        }
    }
}

/// One icon with its name; the selected one gets an accent ring.
private struct AppIconTile: View {
    let name: String
    let image: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    /// The tile; the images carry Apple's grid margin around it, as in the Dock.
    private static let size: CGFloat = 72
    private static let canvas = size / AppIconManager.gridBody
    /// The icons' own corners: 14.3 of 64 units.
    private static let corner = size * 14.3 / 64

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                icon
                    .frame(width: Self.canvas, height: Self.canvas)
                    .overlay(RoundedRectangle(cornerRadius: Self.corner + 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: Self.size + 8, height: Self.size + 8)
                        .opacity(selected ? 1 : 0))
                    .scaleEffect(hovering && !selected ? 1.04 : 1)
                    .animation(.easeOut(duration: 0.15), value: hovering)
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(name) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary))
                .frame(width: Self.size, height: Self.size)
        }
    }
}
