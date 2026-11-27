import AppKit
import CraCEF

@MainActor
final class MainWindowController: NSWindowController {
    let browsers = CaptureTestBrowsers()
    var captureOverlay: CaptureOverlay?
    var captureRequest: (id: UUID, window: NSWindow)?
    var onCaptureFinished: ((CaptureOverlay.Action?, Data?) -> Void)?
    /// Where the last capture came from (page points, the page's size): an easel keeps it.
    var capturedFrom: (rect: CGRect, page: CGSize)?

    var toasts: [String] = []
    func showToast(_ text: String) { toasts.append(text) }

    func captureFinished(_ action: CaptureOverlay.Action?, _ png: Data?, in peek: LittleWindowController? = nil,
                         from: (browser: CraBrowser, rect: CGRect, page: CGSize)? = nil) {
        captureOverlay = nil
        capturedFrom = from.map { ($0.rect, $0.page) }
        onCaptureFinished?(action, png)
    }
}

@MainActor
final class LittleWindowController: NSWindowController {
    var browser: CraBrowser?
    weak var peekParent: MainWindowController?
    weak var captureHost: MainWindowController?
    weak var activeCaptureHost: MainWindowController?
    var isPeek = true
    var isCard = false
    var hasPage = true
    var isParked = false
    var closingPeek = false

    var toasts: [String] = []
    func showToast(_ text: String) { toasts.append(text) }
}

@MainActor
final class CaptureTestBrowsers {
    var visibleRuntime: TabRuntime?
}

@MainActor
final class TabRuntime {
    let browser: CraBrowser
    var hostWindow: NSWindow?

    init(browser: CraBrowser) { self.browser = browser }
}

enum EmbeddedPages {
    static func pageViews(of window: NSWindow) -> [NSView]? { window.contentView?.subviews }
}

/// The app's appearance (Theme.swift's), set by the checks.
final class SystemAppearance: @unchecked Sendable {
    static let shared = SystemAppearance()
    var isDark = true
}
