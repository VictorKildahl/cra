import SwiftUI

/// The pictures on Settings rows for settings that change how Cra looks (see SettingsArt.swift
/// for the parts).
enum SettingsArt {
    /// Favicon colours for made-up tabs.
    static let blue = Color(hex: "#4285F4")
    static let red = Color(hex: "#EA4335")
    static let yellow = Color(hex: "#FBBC05")
    static let green = Color(hex: "#34A853")
    static let purple = Color(hex: "#9B51E0")
}

// MARK: - Tabs

extension SettingsArt {
    /// A new tab lands at the top of the list.
    static var newTabsAtTop: some View {
        let t = ArtTint.lavender
        return ArtCanvas(tint: t) {
            ArtSidebar(tint: t) {
                ArtTabRow(selected: true, symbol: "sparkle", ink: t.ink)
                ArtTabRow(favicon: yellow, title: 0.7)
                ArtTabRow(favicon: green, title: 0.45)
                ArtTabRow(favicon: blue, title: 0.8)
                ArtTabRow(favicon: red, title: 0.55)
            }
            .at(12, 3)
            ArtSymbol(name: "arrow.up", size: 11, color: t.ink, weight: .heavy).at(69, 4)
        }
    }

    /// The New Tab button sits above the tabs instead of under them.
    static var newTabButtonAtTop: some View {
        let t = ArtTint.sky
        return ArtCanvas(tint: t) {
            ArtSidebar(tint: t) {
                ArtTabRow(title: 0.45, selected: true, symbol: "plus", ink: t.ink)
                Rectangle().fill(Color.white.opacity(0.6)).frame(width: 46, height: 0.6).padding(.vertical, 1.5)
                ArtTabRow(favicon: blue, title: 0.7)
                ArtTabRow(favicon: red, title: 0.5)
                ArtTabRow(favicon: green, title: 0.8)
            }
            .at(18, 3)
        }
    }

    /// The open favorite's rim in its logo's colours.
    static var favoriteLogoOutline: some View {
        let t = ArtTint.lemon
        let logo = AngularGradient(colors: [red, yellow, green, blue, red], center: .center)
        return ArtCanvas(tint: t) {
            HStack(spacing: 4) {
                ArtFavorite(logo: blue, width: 20, height: 16)
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.white)
                    .frame(width: 20, height: 16)
                    .overlay(Circle().fill(logo).frame(width: 7, height: 7))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(logo, lineWidth: 1.6).padding(-2))
                ArtFavorite(logo: purple, width: 20, height: 16)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(t.theme))
            .artLift()
            .at(9, 14)
        }
    }

    /// The page reaches the window's edges, with no margin round it.
    static var edgeToEdge: some View {
        let t = ArtTint.sky
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, edgeToEdge: true) {
                VStack(alignment: .leading, spacing: 4) {
                    t.ink.opacity(0.7).frame(height: 16)
                        .overlay(ArtSymbol(name: "arrow.up.left.and.arrow.down.right", size: 8, color: .white, weight: .bold))
                    ArtLines(count: 4, width: 36).padding(.leading, 4)
                }
            }
            .at(9, 5)
        }
    }

    /// The page fills the card, and the toolbar slides in over its top where the pointer is.
    static var autoHideToolbar: some View {
        let t = ArtTint.mint
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t) {
                ZStack(alignment: .topLeading) {
                    ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
                    VStack(spacing: 0) {
                        HStack(spacing: 2) {
                            Capsule().fill(t.ink.opacity(0.7)).frame(width: 22, height: 3)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 3).frame(height: 7)
                        .background(Color.white)
                        Rectangle().fill(Color.black.opacity(0.14)).frame(height: 0.6)
                    }
                    .artLift(1)
                }
            }
            .at(9, 5)
            ArtCursor(size: 8).at(48, 2)
        }
    }

    /// The space's name at the top and its icon at the bottom of the sidebar.
    static var spaceHeader: some View {
        let t = ArtTint.mauve
        return ArtCanvas(tint: t) {
            ArtSidebar(tint: t) {
                HStack(spacing: 3) {
                    ArtSymbol(name: "star.fill", size: 5.5, color: t.ink, weight: .bold)
                    Capsule().fill(Color.black.opacity(0.4)).frame(width: 18, height: 2.6)
                }
                .padding(.horizontal, 3).frame(height: 9)
                ArtTabRow(favicon: blue, title: 0.7, selected: true)
                ArtTabRow(favicon: green, title: 0.5)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Spacer()
                    ArtSymbol(name: "star.fill", size: 5.5, color: t.ink, weight: .bold)
                    Circle().fill(Color.white.opacity(0.6)).frame(width: 2.5, height: 2.5)
                    Spacer()
                }
            }
            .at(18, 3)
        }
    }

}
