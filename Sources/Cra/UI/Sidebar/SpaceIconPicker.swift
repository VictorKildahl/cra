import AppKit
import SwiftUI

/// Arc 1.171's space icon picker (SpaceIconPickerState): a popover under the header's icon with
/// Emoji / Icon tabs and a trash button, a search field, an 8-wide grid that opens on the current
/// emoji's row, and a category bar. Measured from 2x captures (1 Nov): content 272 × 272 pt,
/// cells on a 31 pt pitch, the current emoji on a 27.5 pt rounded tile.
struct SpaceIconPicker: View {
    let current: String
    let currentSymbol: String?
    let onPick: (String) -> Void
    let onPickSymbol: (String) -> Void
    let onRemove: () -> Void

    @State private var tab = 0
    @State private var query = ""
    @State private var hovered: String?
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(31), spacing: 0), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("", selection: $tab) {
                    Text("Emoji").tag(0)
                    Text("Icon").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 105)
                Button(action: onRemove) {
                    Image(systemName: "trash").font(.system(size: 14, weight: .regular))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Remove Icon")
            }
            .padding(.top, 13.5)
            if tab == 0 {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                }
                .padding(.horizontal, 8)
                .frame(height: 27)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(searchFocused ? 0.75 : 0), lineWidth: 3))
                .padding(.horizontal, 8)
                .padding(.top, 9.5)
                emojiGrid
            } else {
                SpaceSymbolGrid(current: currentSymbol, onPick: onPickSymbol)
            }
        }
        .frame(width: 272, height: 272)
        .onAppear {
            tab = currentSymbol == nil ? 0 : 1
            searchFocused = true
        }
    }

    private var emojiGrid: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        if query.isEmpty {
                            // One run across the categories, as in Arc (its 🐦 opens in the second column).
                            ForEach(EmojiCatalog.all, id: \.self) { e in cell(e).id(e.emoji) }
                        } else {
                            ForEach(EmojiCatalog.search(query), id: \.self) { e in cell(e) }
                        }
                    }
                    .padding(.horizontal, 11)
                }
                .padding(.top, 8.5)
                .onAppear { proxy.scrollTo(rowAnchor(current), anchor: .top) }
                Divider().padding(.horizontal, 11)
                HStack(spacing: 0) {
                    ForEach(EmojiCatalog.categories) { c in
                        Button {
                            query = ""
                            proxy.scrollTo(c.entries.first?.emoji, anchor: .top)
                        } label: {
                            Image(systemName: c.symbol).font(.system(size: 13)).frame(width: 31, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func cell(_ e: EmojiCatalog.Entry) -> some View {
        Text(e.emoji)
            .font(.system(size: 21))
            .frame(width: 31, height: 31.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(e.emoji == current ? 0.16 : hovered == e.emoji ? 0.08 : 0))
                    .frame(width: 27.5, height: 27.5)
            )
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? e.emoji : (hovered == e.emoji ? nil : hovered) }
            .onTapGesture { onPick(e.emoji) }
            .help(e.name)
    }

    /// The grid opens with the current emoji's row at the top; rows are 8 wide, so that is the
    /// first emoji of its row.
    private func rowAnchor(_ emoji: String) -> String? {
        guard let i = EmojiCatalog.all.firstIndex(where: { $0.emoji == emoji }) else { return nil }
        return EmojiCatalog.all[i - i % 8].emoji
    }
}

/// The Icon tab: Arc's 56 glyphs in its order (7 rows of 8, no search). Most are SF Symbols in
/// Arc too; its planet, pizza and skull have no SF Symbol and get the nearest one.
struct SpaceSymbolGrid: View {
    let current: String?
    let onPick: (String) -> Void
    @State private var hovered: String?

    static let symbols = [
        "star.fill", "bookmark.fill", "heart.fill", "flag.fill", "bolt.fill", "triangle.fill", "asterisk", "bell.fill",
        "lightbulb.fill", "triangle.circle.fill", "square.grid.2x2.fill", "circle.grid.3x3.fill", "square.stack.3d.up.fill",
        "cylinder.split.1x2.fill", "archivebox.fill", "square.on.square.fill",
        "folder.fill", "tray.full.fill", "calendar", "envelope.fill", "checkmark.square.fill", "doc.fill", "book.fill",
        "ellipsis.bubble.fill",
        "person.2.fill", "apple.terminal.fill", "wrench.and.screwdriver.fill", "square.fill", "oval.portrait.fill",
        "circle.fill", "moon.fill", "sun.max.fill",
        "globe.americas.fill", "leaf.fill", "cloud.fill", "pawprint.fill", "basket.fill", "gift.fill", "bed.double.fill",
        "fork.knife",
        "dumbbell.fill", "airplane", "music.note", "paintpalette.fill", "video.fill", "bandage.fill",
        "chevron.left.forwardslash.chevron.right", "baseball.fill",
        "cloud", "map.fill", "flame.fill", "birthday.cake.fill", "theatermasks.fill", "scroll.fill", "hand.thumbsup.fill",
        "tram.fill",
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 0), count: 8), spacing: 0) {
            ForEach(Self.symbols, id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 31, height: 31)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(name == current ? 0.16 : hovered == name ? 0.1 : 0))
                            .frame(width: 29, height: 29)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
                    .onTapGesture { onPick(name) }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 11)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
