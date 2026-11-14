// Test double for the bridge only. The test runner compiles the production
// BrowserManager.swift unchanged, without loading Chromium or a browser profile.
import AppKit

public protocol CraBrowserDelegate: AnyObject {
    func browserDidClose(_ browser: CraBrowser)
    func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo)
    func browser(_ browser: CraBrowser, requestsPermissionForOrigin origin: String, kinds: UInt, completion: @escaping (Bool) -> Void)
    func browser(_ browser: CraBrowser, didChangeURL url: String)
    func browser(_ browser: CraBrowser, didChangeTitle title: String)
    func browser(_ browser: CraBrowser, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool)
}

extension CraBrowserDelegate {
    public func browser(_ browser: CraBrowser, didUpdateDownload download: CraDownloadInfo) {}
}
public final class CraDownloadInfo { public init() {} }

/// The runtime switches BrowserManager's helpers read.
@MainActor
public enum CraCEFRuntime {
    public static var hosting = true
    public static func chromeHosting() -> Bool { hosting }
}

@objc public enum CraLinkWindow: Int { case new, incognito, little }

/// `open`: the app subclasses it (WebKitBrowser, faked in AppServices.swift).
@MainActor
open class CraBrowser {
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
    public var isAudible = false
    public var hasUncontrollableSound = false
    /// Chrome's pop-up site setting (#357).
    public private(set) var popupsAllowed = false
    public func setPopupsAllowed(_ allowed: Bool) { popupsAllowed = allowed }
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

    /// The saved back and forward list the page was made with (Cra.restoreHistory's params).
    public private(set) var restoredHistory: [String: Any]?
    public convenience init(frame: NSRect, url: String, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?,
                            history: [String: Any]?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        restoredHistory = history
    }

    /// A page made ahead for the next tab (SparePages); `takenURL` is what the tab that took it loads.
    public private(set) var isSpare = false
    public private(set) var takenURL: String?
    public convenience init(spareWithFrame frame: NSRect, profilePath: String?) {
        self.init(frame: frame, url: "", delegate: nil, incognito: false, profilePath: profilePath)
        isSpare = true
    }
    public func takeSpare(withURL url: String, history: [String: Any]?) {
        isSpare = false
        takenURL = url
        currentURL = url
        restoredHistory = history
    }

    public func close() { closeRequested = true; onClose?() }
    public func finishClose() { isClosed = true; delegate?.browserDidClose(self) }
    /// "show" / "close" / "apply <action>", in the order Cra asked.
    public var devToolsRequests: [String] = []
    public func showDevTools() { hasDevTools = true; devToolsRequests.append("show") }
    /// The frontend work asked of the next show (a panel, "inspect"); CEF clears it once done.
    public var devToolsAction: String?
    public func applyDevToolsAction() { devToolsRequests.append("apply \(devToolsAction ?? "")"); devToolsAction = nil }
    public func closeDevTools() { hasDevTools = false; devToolsRequests.append("close") }
    public func setAudioMuted(_ muted: Bool) {}
    public private(set) var backgroundProbes = 0
    public func probeBackgroundColor() { backgroundProbes += 1 }
    public func setFocused(_ focused: Bool) {}
    public private(set) var pictureInPictureRequests = 0
    public private(set) var automaticPictureInPictureRequests = 0
    public func requestPictureInPicture(automatic: Bool) {
        pictureInPictureRequests += 1
        if automatic { automaticPictureInPictureRequests += 1 }
    }
    public func exitPictureInPicture() { isInPictureInPicture = false }
    public private(set) var pictureInPictureCloses = 0
    public func closePictureInPicture() { pictureInPictureCloses += 1; isInPictureInPicture = false }
    public func togglePictureInPicturePlayback() {}
    public func skipPictureInPicture(by seconds: Double) {}
    public func seekPictureInPicture(to seconds: Double) {}
    public private(set) var lastParams = ""
    public func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        lastParams = params
        replies.append((method, completion))
    }
    /// Scripts run in the page's own world (a Boost's JavaScript), in order.
    public private(set) var scripts: [String] = []
    public func executeJavaScript(_ script: String) { scripts.append(script) }
    public private(set) var lastIsolatedParams = ""
    /// Recorded as "<world>:Runtime.evaluate".
    public func evaluate(inIsolatedWorld world: String, params: String, completion: @escaping (String?, String?) -> Void) {
        lastIsolatedParams = params
        replies.append(("\(world):Runtime.evaluate", completion))
    }
    public func reply(to method: String, with result: String?) {
        guard let index = replies.firstIndex(where: { $0.method == method }) else { fatalError("No pending \(method)") }
        replies.remove(at: index).completion(result, nil)
    }
    /// Answers with a protocol error, as CEF does for a method it doesn't have.
    public func fail(_ method: String, with error: String) {
        guard let index = replies.firstIndex(where: { $0.method == method }) else { fatalError("No pending \(method)") }
        replies.remove(at: index).completion(nil, error)
    }
    public func setLoading(_ loading: Bool) {
        isLoading = loading
        delegate?.browser(self, didChangeLoading: loading, canGoBack: false, canGoForward: false)
    }
    /// Addresses Cra asked to load, in order.
    public private(set) var loads: [String] = []
    public func loadURL(_ url: String) { loads.append(url) }
    public func navigate(to url: String) {
        currentURL = url
        delegate?.browser(self, didChangeURL: url)
    }
}
