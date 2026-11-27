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

    /// The room round the page, drawn at the margin the slider sets (Ideas #366): 6 of the picture's points
    /// at Arc's 10, less than one at 1.
    static func pageMargin(_ margin: Double) -> some View {
        let t = ArtTint.lemon
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, margin: CGFloat(PageMargin.clamped(margin)) * 0.6) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
        }
    }

    /// Edge to edge, the page keeps its rounded corners: no margin, only the round (#582).
    static var edgeToEdgeRounded: some View {
        let t = ArtTint.lavender
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, edgeToEdge: true, roundedPage: true) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
        }
    }

    /// The sidebar a dark glass, the desktop's colours showing through it (#366).
    static var translucentSidebar: some View {
        let t = ArtTint.rose
        return ArtCanvas(tint: t) {
            // The desktop behind the window: two soft shapes the glass lets through.
            Circle().fill(ArtTint.lemon.theme).frame(width: 26, height: 26).blur(radius: 1).at(4, 22)
            Circle().fill(ArtTint.sky.theme).frame(width: 22, height: 22).blur(radius: 1).at(-2, 2)
            ArtWindow(tint: t, glass: true) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
        }
    }

    /// The now-playing card at the bottom of the sidebar in the space's own colour, a selected tab's
    /// white over it, with its play controls (#366).
    static var nowPlayingTint: some View {
        let t = ArtTint.mauve
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, rows: 3) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
            ZStack {
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(t.theme.blendedToward(.white, NowPlayingTint.selectedWhite(dark: false)))
                HStack(spacing: 1.6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(t.ink.opacity(0.7)).frame(width: i == 1 ? 2.2 : 1.5, height: i == 1 ? 2.2 : 1.5)
                    }
                }
            }
            .frame(width: 13, height: 6)
            .at(11.5, 42)
        }
    }

    /// The island player at the bottom of the sidebar: a bar with a tab row's corners in the player's own white, its
    /// artwork, a line of title and level bars (Discussion #761).
    static var nowPlayingIsland: some View {
        let t = ArtTint.mauve
        let cover = ArtTint.peach.theme
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, rows: 3) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.2, style: .continuous).fill(t.theme.blendedToward(.white, 0.9))
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 0.7, style: .continuous).fill(cover).frame(width: 3.4, height: 3.4)
                    Capsule().fill(t.ink.opacity(0.6)).frame(width: 3.6, height: 1)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 0.45) {
                        ForEach([1.8, 2.8, 1.3, 2.3], id: \.self) { h in
                            Capsule().fill(t.ink.opacity(0.6)).frame(width: 0.6, height: h)
                        }
                    }
                }
                .padding(.horizontal, 0.9)
            }
            .frame(width: 13, height: 5.4)
            .clipShape(RoundedRectangle(cornerRadius: 1.2, style: .continuous))
            .at(11.5, 42)
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

    /// The sidebar, traffic lights and all, on the window's right (#464).
    static var sidebarOnRight: some View {
        let t = ArtTint.peach
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, sidebarOnRight: true) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 4)
            }
            .at(9, 5)
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

// MARK: - Command bar

extension SettingsArt {
    /// The command bar after Tab on a site: filled with the site's colour, its pill before the field (#457).
    static var commandBarSiteColor: some View {
        let t = ArtTint.rose
        let site = Color(hex: "#FF0000")
        return ArtCanvas(tint: t) {
            ZStack(alignment: .topLeading) {
                Color(red: 75 / 255, green: 35 / 255, blue: 35 / 255)
                HStack(spacing: 3) {
                    Capsule().fill(site).frame(width: 15, height: 6)
                    Capsule().fill(Color.white.opacity(0.45)).frame(width: 22, height: 2.4)
                }
                .at(5, 5)
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 60, height: 0.6).at(5, 15)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(site).frame(width: 60, height: 7)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.9)).frame(width: 30, height: 2.2).padding(.leading, 4)
                        }
                    ArtLines(count: 2, width: 40, color: Color.white.opacity(0.35)).padding(.leading, 4)
                }
                .at(5, 19)
            }
            .frame(width: 70, height: 42, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1)
            .at(9, 7)
        }
    }
}
