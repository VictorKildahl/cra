import AppKit
import SwiftUI

/// Arc's Zap shelf (BoostZap; Arc 1.172.2, measured 12 Nov 2026): a 58 pt bar under the page, in
/// the pane's toolbar colour with a separator on top. Left, a 38 pt cell per zap in the theme's
/// tintedLight with `square.slash` in its ink; a click unzaps, the pointer on one dims the page and
/// turns the hint into "Restore <selector>". With nothing zapped the hint is centred: "Click elements
/// on the page to Zap them". Right, Done in the same tintedLight ends Zap.
struct ZapShelfColors {
    var bar: Color
    var dark: Bool
    /// The cells and Done (the theme's tintedLight).
    var cream: Color
    /// The cell glyph, Done's title and the Restore pill (the theme's ink).
    var ink: Color

    @MainActor static func current(theme: SpaceTheme, toolbarHex: String?) -> ZapShelfColors {
        let shown = theme.shown
        let bar = NSColor(Color(hex: toolbarHex ?? "#FFFFFF")).usingColorSpace(.sRGB) ?? .white
        let luma = 0.299 * bar.redComponent + 0.587 * bar.greenComponent + 0.114 * bar.blueComponent
        let ink = shown.isDark ? Color(NSColor(shown.shadedDark)).blendedToward(.black, 0.7)
                               : SpaceTheme.inkColor(shown.paletteSource ?? "#DDDDDD")
        return ZapShelfColors(bar: Color(bar), dark: luma < 0.5, cream: Color(NSColor(shown.tintedLight)), ink: ink)
    }

    /// The hint's ink on the bar: on a dark bar white tinted by the cream at 90 % (Arc: 233/230/215 on 34).
    var text: Color { dark ? Color.white.blendedToward(cream, 0.3).opacity(0.9) : ink }
    var separator: Color { dark ? .white.opacity(0.1) : .black.opacity(0.1) }
}

struct ZapShelfView: View {
    @Bindable var model: BoostEditorModel
    let colors: ZapShelfColors

    var body: some View {
        let zapped = model.boost.zapped
        let hint = BoostZap.hint(zapped: zapped, hovered: model.hoveredZap)
        ZStack(alignment: .topLeading) {
            colors.bar
            colors.separator.frame(height: 1)
            HStack(spacing: CGFloat(BoostZap.cellGap)) {
                ForEach(Array(zapped.enumerated()), id: \.element) { i, selector in
                    ZapCell(colors: colors, hovered: model.hoveredZap == i) { model.unzap(selector) }
                        .onHover { on in
                            if on { model.hoveredZap = i } else if model.hoveredZap == i { model.hoveredZap = nil }
                        }
                        .help(selector)
                        .accessibilityLabel("Restore \(selector)")
                }
            }
            .padding(.leading, CGFloat(BoostZap.inset))
            .frame(height: CGFloat(BoostZap.shelfHeight))
            hintView(hint, cells: zapped.count)
            HStack {
                Spacer()
                Button { model.toggleZap() } label: {
                    Text("Done").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.ink)
                        .frame(width: CGFloat(BoostZap.doneSize.width), height: CGFloat(BoostZap.doneSize.height))
                        .background(RoundedRectangle(cornerRadius: CGFloat(BoostZap.cellCornerRadius), style: .continuous).fill(colors.cream))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, CGFloat(BoostZap.inset))
            .frame(height: CGFloat(BoostZap.shelfHeight))
        }
        .frame(height: CGFloat(BoostZap.shelfHeight))
    }

    @ViewBuilder private func hintView(_ hint: BoostZap.Hint, cells: Int) -> some View {
        switch hint {
        case .instructions:
            // Centred between the shelf's left inset and Done.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                (Text("Click elements on the page to ") + Text("Zap").fontWeight(.bold).foregroundColor(colors.cream) + Text(" them"))
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(BoostZap.inset))
            .padding(.trailing, CGFloat(BoostZap.inset + BoostZap.doneSize.width))
            .frame(height: CGFloat(BoostZap.shelfHeight))
        case .clickToUnzap:
            HStack(spacing: 4) {
                Image(systemName: "arrow.left").font(.system(size: 11, weight: .semibold))
                Text("Click to unzap").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(colors.text)
            .padding(.leading, CGFloat(BoostZap.hintX(cells: cells, pill: false) - BoostZap.inset))
            .frame(height: CGFloat(BoostZap.shelfHeight))
        case .restore(let selector):
            (Text("Restore ").fontWeight(.bold) + Text(selector))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(colors.text).lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: CGFloat(BoostZap.restorePillHeight))
                .background(Capsule().fill(colors.ink).overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5)))
                .padding(.leading, CGFloat(BoostZap.hintX(cells: cells, pill: true) - BoostZap.inset))
                .frame(height: CGFloat(BoostZap.shelfHeight))
        }
    }
}

private struct ZapCell: View {
    let colors: ZapShelfColors
    let hovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.slash").font(.system(size: CGFloat(BoostZap.glyphSize), weight: .regular))
                .foregroundStyle(colors.ink)
                .frame(width: CGFloat(BoostZap.cellSide), height: CGFloat(BoostZap.cellSide))
                // Arc darkens the cell under the pointer (250/239/198 → 224/213/171).
                .background(RoundedRectangle(cornerRadius: CGFloat(BoostZap.cellCornerRadius), style: .continuous)
                    .fill(hovered ? colors.cream.blendedToward(.black, 0.105) : colors.cream))
        }
        .buttonStyle(.plain)
    }
}

/// The page keeps the keyboard: the shelf's first click acts.
final class ZapShelfHostingView: NSHostingView<ZapShelfView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
