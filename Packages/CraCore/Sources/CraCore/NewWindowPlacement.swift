import CoreGraphics

/// Where New Window (⌘N), New Incognito Window (⇧⌘N), Blank Window (⌃⌘N) and Open Link in New
/// Window put the window they open, from the window in use.
///
/// Windowed, the new one cascades 22 pt down and right of the window in use, back to the top left
/// of its screen when that would leave the screen. In macOS full screen it goes full screen as well,
/// on a Space of its own to the right that a three-finger swipe reaches, as in Safari and Chrome
/// (GitHub #528: it came up as a small window over the full-screen one). Out of full screen it is
/// then the default size, centred on that screen. Little Windows are not opened this way: they stay
/// over the full-screen window.
public enum NewWindowPlacement: Equatable, Sendable {
    /// Windowed at this frame.
    case cascaded(CGRect)
    /// Full screen on the screen holding `windowed`, and at `windowed` once out of it.
    case fullScreen(windowed: CGRect)
    /// No window in use: the window's default place.
    case standard

    /// - Parameters:
    ///   - source: the frame of the window in use, nil when none is on screen.
    ///   - sourceFullScreen: that window is in macOS full screen because the person put it there,
    ///     not only because a page's video went full screen in it.
    ///   - screen: the visible frame of the screen the window in use is on.
    ///   - defaultSize: the size of a new window with nothing to go by.
    public static func of(source: CGRect?, sourceFullScreen: Bool, screen: CGRect?, defaultSize: CGSize) -> Self {
        guard let source else { return .standard }
        if sourceFullScreen {
            let area = screen ?? source
            let size = CGSize(width: min(defaultSize.width, area.width), height: min(defaultSize.height, area.height))
            return .fullScreen(windowed: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                                width: size.width, height: size.height))
        }
        var f = source.offsetBy(dx: 22, dy: -22)
        if let screen, !screen.contains(f) {
            f.origin = CGPoint(x: screen.minX + 22, y: screen.maxY - f.height - 22)
        }
        return .cascaded(f)
    }

    /// The frame the window opens at, nil for its default place.
    public var frame: CGRect? {
        switch self {
        case .cascaded(let f), .fullScreen(let f): f
        case .standard: nil
        }
    }

    public var opensFullScreen: Bool {
        if case .fullScreen = self { true } else { false }
    }
}
