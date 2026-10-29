// Test double for the bridge only. The test runner compiles the production
// BrowserManager.swift unchanged, without loading Chromium or a browser profile.
import AppKit

public protocol CraBrowserDelegate: AnyObject {
    func browserDidClose(_ browser: CraBrowser)
    func browser(_ browser: CraBrowser, didChangeURL url: String)
    func browser(_ browser: CraBrowser, didChangeTitle title: String)
    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool)
}

public final class CraDownloadInfo {}

@MainActor
public final class CraBrowser {
    public weak var delegate: CraBrowserDelegate?
    public let containerView: NSView
    public var hostWindow: NSWindow?
    public var currentURL: String
    public var currentTitle = ""
    public var isCreated = true
    public var isClosed = false
    public var isLoading = false
    public var isInPictureInPicture = false
    public var isPictureInPicturePlaying = false
    public var isCapturingMedia = false
    public var hasDevTools = false
    public var closedByPage = false
    public let isIncognito: Bool
    public let profilePath: String?
    public var userInfo: Any?
    public private(set) var closeRequested = false
    public var onClose: (() -> Void)?
    public var replies: [(method: String, completion: (String?, String?) -> Void)] = []

    public init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?) {
        containerView = NSView(frame: frame)
        currentURL = url ?? ""
        self.delegate = delegate
        isIncognito = incognito
        self.profilePath = profilePath
    }

    public func close() { closeRequested = true; onClose?() }
    public func finishClose() { isClosed = true; delegate?.browserDidClose(self) }
    public func closeDevTools() { hasDevTools = false }
    public func setAudioMuted(_ muted: Bool) {}
    public func setFocused(_ focused: Bool) {}
    public func requestPictureInPicture(automatic: Bool) {}
    public func exitPictureInPicture() { isInPictureInPicture = false }
    public func togglePictureInPicturePlayback() {}
    public func skipPictureInPicture(by seconds: Double) {}
    public func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        replies.append((method, completion))
    }
    public func reply(to method: String, with result: String?) {
        guard let index = replies.firstIndex(where: { $0.method == method }) else { fatalError("No pending \(method)") }
        replies.remove(at: index).completion(result, nil)
    }
    public func setLoading(_ loading: Bool) {
        isLoading = loading
        delegate?.browser(self, didChangeLoading: loading, canGoBack: false, canGoForward: false)
    }
    public func navigate(to url: String) {
        currentURL = url
        delegate?.browser(self, didChangeURL: url)
    }
}
