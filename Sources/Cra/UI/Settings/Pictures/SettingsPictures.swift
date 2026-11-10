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

    /// Hovering a closed folder shows its tabs beside it.
    static var folderPreviews: some View {
        let t = ArtTint.mint
        return ArtCanvas(tint: t) {
            ArtSidebar(tint: t, width: 40) {
                ArtTabRow(favicon: blue, width: 34, title: 0.7)
                ArtTabRow(width: 34, title: 0.6, selected: true, symbol: "folder.fill", ink: t.ink)
                ArtTabRow(favicon: yellow, width: 34, title: 0.5)
                ArtTabRow(favicon: red, width: 34, title: 0.8)
            }
            .at(4, 3)
            ArtCard(width: 38, height: 34) {
                VStack(alignment: .leading, spacing: 1) {
                    ArtTabRow(favicon: green, width: 34, title: 0.8)
                    ArtTabRow(favicon: purple, width: 34, title: 0.55)
                    ArtTabRow(favicon: blue, width: 34, title: 0.7)
                }
                .padding(2)
            }
            .at(46, 9)
            ArtCursor().at(30, 15)
        }
    }

    /// Hovering Gmail's favorite shows the unread mail.
    static var gmailPreviews: some View {
        let t = ArtTint.rose
        return ArtCanvas(tint: t) {
            ArtSidebar(tint: t, width: 44, height: 50) {
                HStack(spacing: 2) {
                    ArtFavorite(logo: red, symbol: "envelope.fill", width: 12, height: 10, selected: true)
                    ArtFavorite(logo: blue, width: 12, height: 10)
                    ArtFavorite(logo: green, width: 12, height: 10)
                }
                .padding(.bottom, 2)
                ArtTabRow(favicon: yellow, width: 38, title: 0.7)
                ArtTabRow(favicon: purple, width: 38, title: 0.5)
                ArtTabRow(favicon: blue, width: 38, title: 0.6)
            }
            .at(4, 3)
            ArtCard(width: 42, height: 38) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(alignment: .top, spacing: 2.5) {
                            Circle().fill(i < 2 ? blue : Color.clear).frame(width: 2.6, height: 2.6).padding(.top, 0.4)
                            ArtLines(count: 2, width: 30, height: 1.8, spacing: 1.5, color: i < 2 ? Color(white: 0.7) : ArtTint.line)
                        }
                    }
                }
                .padding(4)
            }
            .at(42, 14)
            ArtCursor().at(10, 9)
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

    /// Leaving a video's tab floats the video over the next page.
    static var autoPictureInPicture: some View {
        let t = ArtTint.slate
        return ArtCanvas(tint: t) {
            ArtWindow(tint: t, selected: 2).at(4, 5)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color(white: 0.16))
                .frame(width: 32, height: 19)
                .overlay(ArtSymbol(name: "play.fill", size: 7, color: .white))
                .artLift(2)
                .at(50, 31)
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

// MARK: - Links

extension SettingsArt {
    /// A small window with no sidebar, the way a Little Window looks.
    private static func littleWindow(_ t: ArtTint, width: CGFloat = 42, height: CGFloat = 32) -> some View {
        ArtWindow(tint: t, width: width, height: height, sidebar: false, toolbar: true) {
            ArtLines(count: 3, width: width - 14).padding(.leading, 4).padding(.top, 4)
        }
    }

    /// A link clicked in another app opens in a Little Window.
    static var littleWindowFromApps: some View {
        let t = ArtTint.mint
        return ArtCanvas(tint: t) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white)
                .frame(width: 20, height: 20)
                .overlay(ArtSymbol(name: "bubble.left.fill", size: 10, color: SettingsArt.green))
                .artLift()
                .at(6, 18)
            ArtSymbol(name: "arrow.right", size: 8, color: t.ink, weight: .heavy).at(30, 23)
            littleWindow(t).at(42, 12)
        }
    }

    /// A Peek over the page it was opened from.
    private static func peek(_ t: ArtTint, at x: CGFloat, _ y: CGFloat, width: CGFloat = 40, height: CGFloat = 32) -> some View {
        ArtCard(width: width, height: height) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 1.5) {
                    Circle().fill(Color(white: 0.8)).frame(width: 2.4, height: 2.4)
                    Circle().fill(Color(white: 0.8)).frame(width: 2.4, height: 2.4)
                }
                t.theme.opacity(0.6).frame(height: 7).clipShape(RoundedRectangle(cornerRadius: 1))
                ArtLines(count: 3, width: width - 10)
            }
            .padding(3)
        }
        .at(x, y)
    }

    private static func dimmedWindow(_ t: ArtTint) -> some View {
        ArtWindow(tint: t) {
            ZStack(alignment: .topLeading) {
                ArtLines(count: 5, width: 36).padding(.leading, 4).padding(.top, 5)
                Color.black.opacity(0.22)
            }
        }
    }

    /// A link to another site opens in a Peek over the page.
    static var peekLinks: some View {
        let t = ArtTint.lavender
        return ArtCanvas(tint: t) {
            dimmedWindow(t).at(4, 5)
            peek(t, at: 36, 13)
        }
    }

}
