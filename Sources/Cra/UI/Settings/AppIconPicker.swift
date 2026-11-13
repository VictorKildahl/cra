import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Arc's Icon tab (Arc 1.172.2, GitHub #372): a radio list of the app icons, a 64 pt picture and its name on each row,
/// "CURRENT ICON" under the chosen one. Cra's list is its own set, then the user's own image (a row of its own with
/// Remove and Choose Image…; an image dropped on it is used).
struct IconPane: View {
    private let icons = AppIconManager.shared
    @State private var error: String?

    var body: some View {
        SettingsCardPane {
            SettingsCard {
                ForEach(Array(AppIconManager.presets.enumerated()), id: \.element.id) { i, option in
                    if i > 0 { divider }
                    IconRow(name: option.name, image: icons.image(for: option.id), selected: icons.selectedID == option.id) {
                        icons.select(option.id)
                    } trailing: { EmptyView() }
                }
                divider
                IconRow(name: "Your own icon", image: icons.customImage, selected: icons.selectedID == AppIconManager.customID) {
                    if icons.customImage == nil { chooseImage() } else { icons.select(AppIconManager.customID) }
                } trailing: {
                    if icons.customImage != nil {
                        Button("Remove") { icons.removeCustom(); error = nil }
                    }
                    Button("Choose Image…") { chooseImage() }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    use(url)
                    return true
                }
            }
            SettingsFootnote("Pick any image or drop one on “Your own icon”. It’s sized to match the other icons in the Dock, and a photo or a logo on a background fills the rounded tile. The Dock keeps the icon after Cra quits.")
            if let error { SettingsFootnote(error).foregroundStyle(.red) }
        }
    }

    private var divider: some View {
        SettingsCardDivider().padding(.horizontal, 30)
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

/// The icon on its row: the images carry Apple's grid margin around the tile, as in the Dock.
private let iconRowSize: CGFloat = 64
private let iconRowCanvas = iconRowSize / AppIconManager.gridBody
private let iconRowCorner = iconRowSize * 14.3 / 64

/// One row of the list: the radio, the 64 pt icon, its name (14 pt semibold) and "CURRENT ICON" under the chosen one.
private struct IconRow<Trailing: View>: View {
    let name: String
    let image: NSImage?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 0) {
                    radio.padding(.leading, 16)
                    icon.frame(width: iconRowCanvas, height: iconRowCanvas).frame(width: iconRowSize, height: iconRowSize).padding(.leading, 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 14, weight: .semibold))
                        if selected {
                            Text("CURRENT ICON").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.settingsBlue)
                        }
                    }
                    .padding(.leading, 8)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) { trailing }.padding(.trailing, 16)
        }
        .frame(height: 81)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var radio: some View {
        Circle()
            .fill(selected ? Color.settingsBlue : Color.white)
            .overlay(Circle().strokeBorder(selected ? Color.white : Color.clear, lineWidth: 2).padding(1.5))
            .overlay(Circle().strokeBorder(Color.settingsBlue.opacity(selected ? 1 : 0), lineWidth: 1))
            .frame(width: 22, height: 22)
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: iconRowCorner, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary))
                .frame(width: iconRowSize, height: iconRowSize)
        }
    }
}
