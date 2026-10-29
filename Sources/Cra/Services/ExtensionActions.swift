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

    /// Where a popup Cra did not ask for hangs (screen top-right point) for an extension ID, nil
    /// to leave it where Chrome put it.
    private var defaultAnchor: (String) -> NSPoint? = { _ in nil }
    /// True while `run` waits for its own popup.
    private var placingOwnPopup = false

    /// Popups can open without Cra's buttons: the extension's keyboard shortcut (1Password's
    /// ⌘⇧X) or chrome.action.openPopup() (1Password's inline menu). Arc hosts every popup
    /// under its toolbar (ArcCore hands it over in browser:didOpenExtensionPopup:webContents:);
    /// Cra watches for popup pages being created and moves those under `anchor` too.
    func watchPopups(anchor: @escaping (String) -> NSPoint?) {
        defaultAnchor = anchor
        guard isAvailable else { return }
        Task { _ = try? await call("Target.setDiscoverTargets", ["discover": true]) }
    }

    /// Triggers the action; `anchor` is the top-right point (screen coordinates) the popup hangs from.
    /// Returns false when the pipe or the page is unavailable (the caller falls back).
    @discardableResult
    func run(_ extensionID: String, on browser: CraBrowser, anchor: NSPoint) async -> Bool {
        guard isAvailable else { return false }
        var triggered = false
        HitchMonitor.mark("extension request \(extensionID)")
        do {
            let tab = try await tabTarget(for: browser)
            let before = visibleWindows()
            placingOwnPopup = true
            triggered = true
            HitchMonitor.mark("extension trigger \(extensionID)")
            _ = try await call("Extensions.triggerAction", ["id": extensionID, "targetId": tab])
            HitchMonitor.mark("extension trigger-replied \(extensionID)")
            placePopup(appearingAfter: before, anchor: anchor, sourceHost: browser.hostWindow)
            return true
        } catch {
            placingOwnPopup = false
            NSLog("Cra: extension action %@ failed: %@", extensionID, String(describing: error))
            tabTargets[ObjectIdentifier(browser)] = nil
            // The action may still run after its reply timed out; a fallback page would be a
            // second popup.
            return triggered && error is ExtensionProtocolTimeout
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
    private func placePopup(appearingAfter before: Set<ObjectIdentifier>, anchor: NSPoint, sourceHost: NSWindow? = nil, attempt: Int = 0) {
        // Sharing badges and tooltips can also become visible during startup. A popup
        // must belong to a Chromium page in the browser containing the resolved anchor.
        if let popup = NSApp.windows.first(where: { candidate in
            guard !before.contains(ObjectIdentifier(candidate)),
                  let owner = sourceHost?.parent ?? candidate.parent?.parent,
                  owner.frame.contains(anchor) else { return false }
            return ExtensionPopupCandidate.matches(candidate, owner: owner, sourceHost: sourceHost,
                                                   isPageHost: CraCEFRuntime.isPageWindow)
        }) {
            HitchMonitor.mark("extension present window=\(popup.windowNumber) frame=\(NSStringFromRect(popup.frame)) parent=\(popup.parent?.windowNumber ?? -1)")
            placingOwnPopup = false
            ExtensionPopupWindow.present(popup, anchor: anchor)
            return
        }
        // No popup yet (still loading), or an action without one (onClicked): keep looking for 3 s.
        guard attempt < 60 else {
            HitchMonitor.mark("extension placement-expired source=\(sourceHost?.windowNumber ?? -1)")
            placingOwnPopup = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.placePopup(appearingAfter: before, anchor: anchor, sourceHost: sourceHost, attempt: attempt + 1) }
        }
    }

    // MARK: Targets

    private enum Failure: Error { case protocolError(String), noTabTarget }

    /// The tab target that holds this browser's page: attach to each tab target and let it
    /// auto-attach its page (the protocol has no direct page → tab link). Cached per browser.
    private func tabTarget(for browser: CraBrowser) async throws -> String {
        if let cached = tabTargets[ObjectIdentifier(browser)], cached.browser === browser { return cached.tabTarget }
        let info = try await pageCall(browser, "Target.getTargetInfo")
        guard let page = info["targetInfo"] as? [String: Any], let pageID = page["targetId"] as? String else { throw Failure.noTabTarget }
        let url = page["url"] as? String
        let tabs = (try await call("Target.getTargets", ["filter": [["type": "tab"]]])["targetInfos"] as? [[String: Any]]) ?? []
        // Same URL first: usually the only one that needs checking.
        let ordered = tabs.filter { $0["url"] as? String == url } + tabs.filter { $0["url"] as? String != url }
        for tab in ordered {
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
              let id = url.host, url.fragment == nil,
              let popup = ExtensionStore.shared.entries.first(where: { $0.extensionID == id })?.popupPath,
              url.path == "/" + popup.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              seenPopupTargets.insert(target).inserted, !placingOwnPopup,
              let anchor = defaultAnchor(id) else { return }
        placePopup(appearingAfter: visibleWindows(), anchor: anchor)
    }

    // MARK: Protocol calls

    // Chromium can leave a request unanswered (its target went away meanwhile). Without a
    // deadline `placingOwnPopup` stayed set and no later shortcut popup was placed.
    private func call(_ method: String, _ params: [String: Any] = [:], session: String? = nil) async throws -> [String: Any] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: params), as: UTF8.self)
        return try await withCheckedThrowingContinuation { cont in
            let reply = ExtensionProtocolReply<[String: Any]>(method: method, timeout: 5, onLateReply: { result in
                // An attach that answers after its caller gave up still leaves a session open.
                if method == "Target.attachToTarget", case let .success(object) = result,
                   let session = object["sessionId"] as? String {
                    CraCEFRuntime.sendBrowserDevToolsMethod("Target.detachFromTarget", params: #"{"sessionId":"\#(session)"}"#,
                                                            sessionID: nil) { _, _ in }
                }
            }) { cont.resume(with: $0) }
            CraCEFRuntime.sendBrowserDevToolsMethod(method, params: json, sessionID: session) { result, error in
                MainActor.assumeIsolated { reply.resolve(Self.result(result, error: error, method: method)) }
            }
        }
    }

    private func pageCall(_ browser: CraBrowser, _ method: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            let reply = ExtensionProtocolReply<[String: Any]>(method: method, timeout: 5) { cont.resume(with: $0) }
            browser.sendDevToolsMethod(method, params: "{}") { result, error in
                MainActor.assumeIsolated { reply.resolve(Self.result(result, error: error, method: method)) }
            }
        }
    }

    private nonisolated static func result(_ result: String?, error: String?, method: String) -> Result<[String: Any], Error> {
        if let result, let obj = try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] { return .success(obj) }
        return .failure(Failure.protocolError(error ?? "bad reply to \(method)"))
    }
}
