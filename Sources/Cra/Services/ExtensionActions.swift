import AppKit
import CraCEF

/// Runs an extension's toolbar action on a page the way a click on its Chrome
/// toolbar button does: `Extensions.triggerAction` over the browser-level DevTools
/// pipe. Chrome then opens the real popup (with activeTab granted) or fires
/// chrome.action.onClicked. The popup anchors to the page's hidden Chrome toolbar,
/// so Cra frames it in a window under its own button (Arc: right edges aligned, just below the bar).
@MainActor
final class ExtensionActions {
    static let shared = ExtensionActions()

    private struct CachedTab { weak var browser: CraBrowser?; let tabTarget: String }
    /// Page browser → its "tab" target (triggerAction only accepts tab targets).
    private var tabTargets: [ObjectIdentifier: CachedTab] = [:]
    /// Tab session → callback with the page target that auto-attaches under it.
    private var childWaiters: [String: (String?) -> Void] = [:]

    var isAvailable: Bool { CraCEFRuntime.hasBrowserDevTools() }

    private init() {
        // The pipe delivers on the main queue.
        CraCEFRuntime.setBrowserDevToolsEventHandler { [weak self] method, params, sessionID in
            MainActor.assumeIsolated { self?.handleEvent(method, params: params, sessionID: sessionID) }
        }
    }

    /// Resolve by extension identity so shortcuts use the same button as a toolbar click.
    private var defaultAnchor: (String) -> ExtensionPopupAnchor? = { _ in nil }
    /// Only the latest invocation may place a popup. An older asynchronous callback must
    /// not move a newer popup back to the previous invocation's window or button.
    private var placementRequest: UUID?
    private final class PendingPopup {
        let extensionID: String
        var matcher: ExtensionPopupRequest?
        var targets: Set<String> = []
        init(_ extensionID: String) { self.extensionID = extensionID }
    }
    private var pendingPopup: PendingPopup?

    /// Popups can open without Cra's buttons: the extension's keyboard shortcut (1Password's
    /// ⌘⇧X) or chrome.action.openPopup() (1Password's inline menu). Arc hosts every popup
    /// under its toolbar (ArcCore hands it over in browser:didOpenExtensionPopup:webContents:);
    /// Cra watches for popup pages being created and moves those under `anchor` too.
    func watchPopups(anchor: @escaping (String) -> ExtensionPopupAnchor?) {
        defaultAnchor = anchor
        guard isAvailable else { return }
        Task { _ = try? await call("Target.setDiscoverTargets", ["discover": true]) }
    }

    /// Resolve `anchor` only when the popup appears, after Chromium's asynchronous work.
    /// Returns false when the pipe or the page is unavailable (the caller falls back).
    @discardableResult
    func run(_ extensionID: String, on browser: CraBrowser, anchor: @escaping () -> ExtensionPopupAnchor?) async -> Bool {
        guard isAvailable else { return false }
        let request = UUID()
        HitchMonitor.mark("extension request \(request) \(extensionID)")
        placementRequest = request
        let pending = PendingPopup(extensionID)
        pendingPopup = pending
        var triggerSent = false
        // A cold lookup can inspect several tab targets; bound the whole startup too,
        // rather than multiplying a per-command timeout by the number of open tabs.
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.placementRequest == request else { return }
            self.finishPlacement(request)
            self.closeCancelledPopups(pending)
            HitchMonitor.mark("extension startup-expired \(request)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: deadline)
        defer { deadline.cancel() }
        do {
            let tab = try await tabTarget(for: browser, request: request)
            guard placementRequest == request else { return true }
            let targets = (try await call("Target.getTargets"))["targetInfos"] as? [[String: Any]] ?? []
            guard placementRequest == request else { return true }
            guard anchor() != nil else { finishPlacement(request); return true }
            if let path = ExtensionStore.shared.entries.first(where: { $0.extensionID == extensionID })?.popupPath {
                pending.matcher = ExtensionPopupRequest(extensionID: extensionID, popupPath: path,
                                                       existingTargets: Set(targets.compactMap { $0["targetId"] as? String }))
            }
            let before = visibleWindows()
            HitchMonitor.mark("extension trigger \(request)")
            triggerSent = true
            _ = try await call("Extensions.triggerAction", ["id": extensionID, "targetId": tab])
            HitchMonitor.mark("extension trigger-replied \(request)")
            guard placementRequest == request else { return true }
            placePopup(appearingAfter: before, anchor: anchor, request: request, pending: pending)
            return true
        } catch {
            guard placementRequest == request else { return true }
            finishPlacement(request)
            NSLog("Cra: extension action %@ failed: %@", extensionID, String(describing: error))
            tabTargets[ObjectIdentifier(browser)] = nil
            if triggerSent, error is ExtensionProtocolTimeout {
                // The action may already have executed. Opening a fallback page now
                // would create a second popup and could steal focus after the failure.
                closeCancelledPopups(pending)
                return true
            }
            return false
        }
    }

    // MARK: Popup placement

    /// Chrome creates the popup's window hidden, sometimes before the popup page exists, so
    /// "new" means newly visible.
    private func visibleWindows() -> Set<ObjectIdentifier> {
        Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
    }

    /// Chrome shows the popup once its page has loaded; watch for the new window and frame it
    /// under the anchor (ExtensionPopupWindow, Arc's BrowserExtensionWindow).
    private func placePopup(appearingAfter before: Set<ObjectIdentifier>, anchor: @escaping () -> ExtensionPopupAnchor?, request: UUID,
                            pending: PendingPopup? = nil, attempt: Int = 0) {
        guard placementRequest == request else { return }
        // A tab can change while Chromium waits for its renderer. Cancel only a target
        // created for this request and verified by Chrome as a real extension popup.
        guard let resolved = anchor() else {
            if let pending, !pending.targets.isEmpty {
                finishPlacement(request)
                closeCancelledPopups(pending)
                return
            }
            // The target may still be blank; retain the request until its URL arrives.
            guard attempt < 60 else { finishPlacement(request); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.placePopup(appearingAfter: before, anchor: anchor, request: request, pending: pending, attempt: attempt + 1)
            }
            return
        }
        // Chrome's popup bubble is borderless; an extension's own (titled) window is not one.
        if let popup = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 1
                                                    && !$0.styleMask.contains(.titled) && !($0 is NSPanel)
                                                    && !CraCEFRuntime.isPageWindow($0) }) {
            HitchMonitor.mark("extension present \(request)")
            finishPlacement(request)
            ExtensionPopupWindow.present(popup, anchor: resolved)
            return
        }
        // No popup yet (still loading), or an action without one (onClicked): keep looking for 3 s.
        guard attempt < 60 else { finishPlacement(request); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.placePopup(appearingAfter: before, anchor: anchor, request: request, pending: pending, attempt: attempt + 1) }
        }
    }

    private func finishPlacement(_ request: UUID) {
        guard placementRequest == request else { return }
        placementRequest = nil
        pendingPopup = nil
    }

    private func closeCancelledPopups(_ pending: PendingPopup) {
        for target in pending.targets {
            Task {
                guard let attached = try? await cleanupCall("Target.attachToTarget", ["targetId": target, "flatten": true]),
                      let session = attached["sessionId"] as? String else { return }
                _ = try? await cleanupCall("Runtime.evaluate", ["expression": ExtensionPopupRequest.closeExpression(extensionID: pending.extensionID),
                                                               "returnByValue": true], session: session)
                _ = try? await cleanupCall("Target.detachFromTarget", ["sessionId": session])
            }
        }
    }

    // MARK: Targets

    private enum Failure: Error { case protocolError(String), noTabTarget, cancelled }

    /// The tab target that holds this browser's page: attach to each tab target and let it
    /// auto-attach its page (the protocol has no direct page → tab link). Cached per browser.
    private func tabTarget(for browser: CraBrowser, request: UUID) async throws -> String {
        guard !browser.isClosed else { throw Failure.noTabTarget }
        if let cached = tabTargets[ObjectIdentifier(browser)], cached.browser === browser { return cached.tabTarget }
        let info = try await pageCall(browser, "Target.getTargetInfo")
        guard let page = info["targetInfo"] as? [String: Any], let pageID = page["targetId"] as? String else { throw Failure.noTabTarget }
        let url = page["url"] as? String
        let tabs = (try await call("Target.getTargets", ["filter": [["type": "tab"]]])["targetInfos"] as? [[String: Any]]) ?? []
        // Same URL first: usually the only one that needs checking.
        let ordered = tabs.filter { $0["url"] as? String == url } + tabs.filter { $0["url"] as? String != url }
        for tab in ordered {
            guard placementRequest == request, !browser.isClosed else { throw Failure.cancelled }
            guard let tabID = tab["targetId"] as? String else { continue }
            if try await pageTarget(inTab: tabID) == pageID {
                tabTargets[ObjectIdentifier(browser)] = CachedTab(browser: browser, tabTarget: tabID)
                return tabID
            }
        }
        throw Failure.noTabTarget
    }

    private func pageTarget(inTab tabID: String) async throws -> String? {
        let attached = try await call("Target.attachToTarget", ["targetId": tabID, "flatten": true])
        guard let session = attached["sessionId"] as? String else { return nil }
        let page: String? = await withCheckedContinuation { cont in
            childWaiters[session] = { cont.resume(returning: $0) }
            Task {
                _ = try? await self.call("Target.setAutoAttach", ["autoAttach": true, "waitForDebuggerOnStart": false, "flatten": true],
                                         session: session)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                MainActor.assumeIsolated { self?.childWaiters.removeValue(forKey: session)?(nil) }
            }
        }
        _ = try? await call("Target.detachFromTarget", ["sessionId": session])
        return page
    }

    private func handleEvent(_ method: String, params: String, sessionID: String?) {
        if method == "Target.targetDestroyed",
           let p = try? JSONSerialization.jsonObject(with: Data(params.utf8)) as? [String: Any],
           let target = p["targetId"] as? String {
            seenPopupTargets.remove(target)
            pendingPopup?.targets.remove(target)
            tabTargets = tabTargets.filter { $0.value.browser != nil && $0.value.tabTarget != target }
            return
        }
        if method == "Target.targetCreated" || method == "Target.targetInfoChanged" { popupPageCreated(params); return }
        guard method == "Target.attachedToTarget", let sessionID, childWaiters[sessionID] != nil,
              let p = try? JSONSerialization.jsonObject(with: Data(params.utf8)) as? [String: Any],
              let info = p["targetInfo"] as? [String: Any], info["type"] as? String == "page" else { return }
        childWaiters.removeValue(forKey: sessionID)?(info["targetId"] as? String)
    }

    /// Popup targets already seen (each is placed once).
    private var seenPopupTargets: Set<String> = []

    /// A target for an extension's popup URL that Cra's own `run` is not waiting for. Chrome
    /// creates it blank ("other", no URL) and reports the URL in a later targetInfoChanged.
    private func popupPageCreated(_ params: String) {
        guard let p = try? JSONSerialization.jsonObject(with: Data(params.utf8)) as? [String: Any],
              let info = p["targetInfo"] as? [String: Any], let target = info["targetId"] as? String,
              let url = (info["url"] as? String).flatMap(URL.init(string:)), url.scheme == "chrome-extension",
              let id = url.host,
              let popup = ExtensionStore.shared.entries.first(where: { $0.extensionID == id })?.popupPath,
              url.path == "/" + popup.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !seenPopupTargets.contains(target) else { return }
        // A popup may navigate to a fragment (Bitwarden's router does). It is still the
        // same target. Do not mark it seen until there is an owner that can anchor it.
        if placementRequest != nil {
            if let pending = pendingPopup, pending.matcher?.matches(info) == true { pending.targets.insert(target) }
            seenPopupTargets.insert(target)
            return
        }
        guard defaultAnchor(id) != nil else { return }
        seenPopupTargets.insert(target)
        let request = UUID()
        placementRequest = request
        placePopup(appearingAfter: visibleWindows(), anchor: { [weak self] in self?.defaultAnchor(id) }, request: request)
    }

    // MARK: Protocol calls

    /// Cleanup uses a shorter deadline than startup and never blocks a new invocation.
    private func cleanupCall(_ method: String, _ params: [String: Any], session: String? = nil) async throws -> [String: Any] {
        try await call(method, params, session: session, timeout: 2)
    }

    private func call(_ method: String, _ params: [String: Any] = [:], session: String? = nil, timeout: TimeInterval = 5) async throws -> [String: Any] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
        return try await withCheckedThrowingContinuation { cont in
            let reply = ExtensionProtocolReply<[String: Any]>(method: method, timeout: timeout, onLateReply: { result in
                // An attach can succeed after its caller has timed out. Release that
                // session instead of leaving the extension inspected indefinitely.
                if method == "Target.attachToTarget", case let .success(object) = result,
                   let session = object["sessionId"] as? String,
                   let data = try? JSONSerialization.data(withJSONObject: ["sessionId": session]) {
                    CraCEFRuntime.sendBrowserDevToolsMethod("Target.detachFromTarget", params: String(decoding: data, as: UTF8.self)) { _, _ in }
                }
            }) { cont.resume(with: $0) }
            CraCEFRuntime.sendBrowserDevToolsMethod(method, params: json, sessionID: session) { result, error in
                reply.resolve(Self.protocolResult(result, error: error, method: method))
            }
        }
    }

    private func pageCall(_ browser: CraBrowser, _ method: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            let reply = ExtensionProtocolReply<[String: Any]>(method: method, timeout: 5) { cont.resume(with: $0) }
            browser.sendDevToolsMethod(method, params: "{}") { result, error in
                reply.resolve(Self.protocolResult(result, error: error, method: method))
            }
        }
    }

    private static func protocolResult(_ result: String?, error: String?, method: String) -> Result<[String: Any], Error> {
        if let result, let object = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] { return .success(object) }
        return .failure(Failure.protocolError(error ?? "bad reply to \(method)"))
    }
}
