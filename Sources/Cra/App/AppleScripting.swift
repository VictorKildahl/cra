import AppKit
import CraCEF

/// Arc's AppleScript dictionary (Arc 1.172.1's Arc.sdef, the same terms and four-letter codes in
/// resources/Cra.sdef, so scripts and launcher extensions written for Arc work against Cra):
/// windows, their tabs and spaces; make new tab, select, go back/forward, reload, stop, close,
/// focus a space. `execute javascript` runs only while View ▸ Developer ▸ Allow JavaScript from
/// Apple Events is on (off by default, as in Arc). macOS asks before any app may script Cra.

extension AppDelegate {
    @objc func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        ["appleScriptWindows", "appleScriptTabs"].contains(key)
    }

    /// The browser windows, front to back.
    @objc var appleScriptWindows: [AppleScriptWindowWrapper] {
        let order = NSApp.orderedWindows
        return mainWindows
            .filter { $0.window?.isVisible == true || $0.window?.isMiniaturized == true }
            .sorted { a, b in (order.firstIndex { $0 === a.window } ?? .max) < (order.firstIndex { $0 === b.window } ?? .max) }
            .map(AppleScriptWindowWrapper.init)
    }

    /// Arc: a write-only collection that makes a Little Arc; here a Little Window.
    @objc var appleScriptTabs: [AppleScriptTabWrapper] { [] }

    @objc func insertInAppleScriptTabs(_ tab: AppleScriptTabWrapper) {
        _ = openLittleWindow(url: tab.pendingURL ?? "")
    }
}

@MainActor
@objc(AppleScriptWindowWrapper)
final class AppleScriptWindowWrapper: NSObject {
    let controller: MainWindowController
    init(_ controller: MainWindowController) { self.controller = controller }
    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }
    private var store: SidebarStore { controller.store }

    @objc var id: String { controller.windowID.uuidString }
    @objc var title: String { controller.window?.title ?? "" }
    @objc var orderedIndex: Int { (app?.appleScriptWindows.firstIndex { $0.controller === controller } ?? 0) + 1 }
    @objc var hasCloseBox: Bool { true }
    @objc var isMiniaturizable: Bool { true }
    @objc var isMiniaturized: Bool {
        get { controller.window?.isMiniaturized ?? false }
        set { newValue ? controller.window?.miniaturize(nil) : controller.window?.deminiaturize(nil) }
    }
    @objc var isResizable: Bool { true }
    @objc var isVisible: Bool {
        get { controller.window?.isVisible ?? false }
        set { newValue ? controller.showWindow(nil) : controller.window?.orderOut(nil) }
    }
    @objc var isZoomable: Bool { true }
    @objc var isZoomed: Bool {
        get { controller.window?.isZoomed ?? false }
        set { if newValue != isZoomed { controller.window?.zoom(nil) } }
    }
    @objc var isIncognito: Bool { controller.isIncognito }
    @objc var mode: String { controller.isIncognito ? "incognito" : "normal" }

    @objc var activeTab: AppleScriptTabWrapper? { controller.selectedTabID.map { AppleScriptTabWrapper(tab: $0, window: self) } }
    @objc var activeSpace: AppleScriptSpaceWrapper? { AppleScriptSpaceWrapper(space: controller.focusedSpaceID, window: self) }

    /// The window's space's tabs, as its sidebar lists them: favorites, pinned, then Today.
    @objc var appleScriptTabs: [AppleScriptTabWrapper] {
        tabIDs(in: controller.focusedSpaceID).map { AppleScriptTabWrapper(tab: $0, window: self) }
    }

    @objc var appleScriptSpaces: [AppleScriptSpaceWrapper] {
        guard !controller.isStandalone else { return [AppleScriptSpaceWrapper(space: controller.focusedSpaceID, window: self)] }
        return store.orderedSpaces.filter { !store.isStandalone(space: $0.id) }.map { AppleScriptSpaceWrapper(space: $0.id, window: self) }
    }

    func tabIDs(in spaceID: UUID) -> [UUID] {
        guard let space = store.space(spaceID) else { return [] }
        return (store.tabs(under: space.favoritesContainerID) + store.tabs(under: space.pinnedContainerID)
            + store.tabs(under: space.todayContainerID)).map(\.id)
    }

    /// make new tab at end of tabs of window 1 with properties {URL:"…"}: a Today tab, opened.
    @objc func insertInAppleScriptTabs(_ tab: AppleScriptTabWrapper) {
        let url = tab.pendingURL ?? ""
        if url.isEmpty { controller.openCommandBar(.newTab); return }
        let item = store.createTab(url: url, in: controller.focusedSpaceID, select: true, window: controller.windowID)
        tab.attach(item.id, window: self)
    }

    @objc func close(_ command: NSScriptCommand) -> Any? {
        controller.window?.performClose(nil)
        return nil
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: appDescription, containerSpecifier: nil,
                                   key: "appleScriptWindows", uniqueID: id)
    }
}

@MainActor
@objc(AppleScriptSpaceWrapper)
final class AppleScriptSpaceWrapper: NSObject {
    let spaceID: UUID
    let window: AppleScriptWindowWrapper
    init(space: UUID, window: AppleScriptWindowWrapper) { (spaceID, self.window) = (space, window) }

    @objc var id: String { spaceID.uuidString }
    @objc var title: String {
        let space = window.controller.store.space(spaceID)
        return window.controller.isBlank ? "This Window" : space?.title ?? ""
    }
    @objc var appleScriptTabs: [AppleScriptTabWrapper] {
        window.tabIDs(in: spaceID).map { AppleScriptTabWrapper(tab: $0, window: window) }
    }

    @objc func focus(_ command: NSScriptCommand) -> Any? {
        window.controller.store.focusSpace(spaceID, window: window.controller.windowID)
        return nil
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let container = window.objectSpecifier, let desc = container.keyClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: desc, containerSpecifier: container, key: "appleScriptSpaces", uniqueID: id)
    }
}

@MainActor
@objc(AppleScriptTabWrapper)
final class AppleScriptTabWrapper: NSObject {
    private(set) var tabID: UUID?
    private(set) weak var window: AppleScriptWindowWrapper?
    private var windowRef: AppleScriptWindowWrapper?
    /// What `make new tab with properties {URL:…}` set before the tab exists.
    var pendingURL: String?

    /// Cocoa scripting makes a new one with init() for `make new tab`.
    override init() { super.init() }
    init(tab: UUID, window: AppleScriptWindowWrapper) {
        tabID = tab
        windowRef = window
        super.init()
        self.window = window
    }

    func attach(_ tab: UUID, window: AppleScriptWindowWrapper) {
        tabID = tab
        windowRef = window
        self.window = window
    }

    private var controller: MainWindowController? { window?.controller }
    private var store: SidebarStore? { controller?.store }
    private var item: SidebarItem? { tabID.flatMap { store?.item($0) } }
    private var browser: CraBrowser? { tabID.flatMap { (NSApp.delegate as? AppDelegate)?.runtime(for: $0)?.browser } }

    @objc var id: String { tabID?.uuidString ?? "" }
    @objc var title: String { item?.displayTitle ?? "" }
    @objc var URL: String {
        get { item?.tab?.url ?? pendingURL ?? "" }
        set {
            guard let tabID, let controller else { pendingURL = newValue; return }
            controller.store.updateTab(tabID, url: newValue)
            browser?.loadURL(newValue)
        }
    }
    @objc var loading: Bool { browser?.isLoading ?? false }
    @objc var location: String {
        guard let tabID, let store else { return "unpinned" }
        if store.isFavorite(tabID) { return "topApp" }
        return store.isPinned(tabID) ? "pinned" : "unpinned"
    }

    @objc func select(_ command: NSScriptCommand) -> Any? {
        guard let tabID, let controller else { return nil }
        controller.store.selectTab(tabID, window: controller.windowID)
        controller.showWindow(nil)
        return nil
    }
    @objc func goBack(_ command: NSScriptCommand) -> Any? { browser?.goBack(); return nil }
    @objc func goForward(_ command: NSScriptCommand) -> Any? { browser?.goForward(); return nil }
    @objc func reload(_ command: NSScriptCommand) -> Any? { browser?.reload(); return nil }
    @objc func stopLoading(_ command: NSScriptCommand) -> Any? { browser?.stopLoading(); return nil }
    @objc func close(_ command: NSScriptCommand) -> Any? {
        if let tabID { controller?.closeTab(tabID) }
        return nil
    }

    /// Arc's `execute … javascript "…"`: the result as text. Refused while the Developer menu's
    /// Allow JavaScript from Apple Events is off, and for a tab whose page isn't loaded.
    @objc func executeJavascript(_ command: NSScriptCommand) -> Any? {
        guard store?.settings.allowAppleEventsJavaScript == true else {
            command.scriptErrorNumber = -1723  // errAEAccessorNotFound's neighbour: "access not allowed"
            command.scriptErrorString = "Executing JavaScript through AppleScript is turned off. To turn it on, choose View ▸ Developer ▸ Allow JavaScript from Apple Events in Cra."
            return nil
        }
        guard let js = command.evaluatedArguments?["javascript"] as? String, let browser else {
            command.scriptErrorNumber = -1728
            command.scriptErrorString = "The tab has no page loaded."
            return nil
        }
        guard let params = try? JSONSerialization.data(withJSONObject: ["expression": js, "returnByValue": true, "awaitPromise": true]),
              let json = String(data: params, encoding: .utf8) else { return nil }
        command.suspendExecution()
        browser.sendDevToolsMethod("Runtime.evaluate", params: json) { result, error in
            let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            let value = (o?["result"] as? [String: Any])?["value"]
            let text: String
            switch value {
            case let s as String: text = s
            case nil: text = error ?? ""
            case let v?: text = (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "\(v)"
            }
            command.resumeExecution(withResult: text)
        }
        return nil
    }

    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let window, let container = window.objectSpecifier, let desc = container.keyClassDescription else { return nil }
        return NSUniqueIDSpecifier(containerClassDescription: desc, containerSpecifier: container, key: "appleScriptTabs", uniqueID: id)
    }
}
