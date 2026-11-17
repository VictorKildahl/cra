import AppKit
import CraCEF

/// Arc's AppleScript dictionary (Arc 1.172.1's Arc.sdef, the same terms and four-letter codes in
/// resources/Cra.sdef, so scripts and launcher extensions written for Arc work against Cra):
/// windows, their tabs (every space's, #428) and spaces; make new window, make new tab, select,
/// go back/forward, reload, stop, close, focus a space. `execute javascript` runs only while View ▸ Developer ▸ Allow JavaScript from
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
            .map { AppleScriptWindowWrapper($0) }
    }

    /// make new window [with properties {incognito:true}] (Arc; Raycast's Arc extension sends it
    /// for New Window and New Incognito Window, GitHub #427): File ▸ New Window's window, or New
    /// Incognito Window's, which the command returns.
    @objc func insertInAppleScriptWindows(_ window: AppleScriptWindowWrapper) {
        window.attach(openNewWindow(incognito: window.isIncognito))
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
    /// Nil only between `make new window`'s init() and the window opening.
    private(set) var controller: MainWindowController?
    /// What `make new window with properties {incognito:…}` (or `{mode:…}`) set before the window exists.
    private var pendingIncognito = false

    /// Cocoa scripting makes a new one with init() for `make new window`, sets its properties,
    /// then hands it to the app delegate's insertInAppleScriptWindows(_:).
    override init() { super.init() }
    init(_ controller: MainWindowController) {
        self.controller = controller
        super.init()
    }

    func attach(_ controller: MainWindowController) { self.controller = controller }

    private var app: AppDelegate? { NSApp.delegate as? AppDelegate }

    @objc var id: String { controller?.windowID.uuidString ?? "" }
    @objc var title: String { controller?.window?.title ?? "" }
    @objc var orderedIndex: Int {
        guard let controller else { return 0 }
        return (app?.appleScriptWindows.firstIndex { $0.controller === controller } ?? 0) + 1
    }
    @objc var hasCloseBox: Bool { true }
    @objc var isMiniaturizable: Bool { true }
    @objc var isMiniaturized: Bool {
        get { controller?.window?.isMiniaturized ?? false }
        set { newValue ? controller?.window?.miniaturize(nil) : controller?.window?.deminiaturize(nil) }
    }
    @objc var isResizable: Bool { true }
    @objc var isVisible: Bool {
        get { controller?.window?.isVisible ?? false }
        set { newValue ? controller?.showWindow(nil) : controller?.window?.orderOut(nil) }
    }
    @objc var isZoomable: Bool { true }
    @objc var isZoomed: Bool {
        get { controller?.window?.isZoomed ?? false }
        set { if newValue != isZoomed { controller?.window?.zoom(nil) } }
    }
    /// Arc: "can be set only once during creation of the window".
    @objc var isIncognito: Bool {
        get { controller?.isIncognito ?? pendingIncognito }
        set { if controller == nil { pendingIncognito = newValue } else { refuseModeChange() } }
    }
    @objc var mode: String {
        get { isIncognito ? "incognito" : "normal" }
        set { if controller == nil { pendingIncognito = newValue == "incognito" } else { refuseModeChange() } }
    }

    private func refuseModeChange() {
        let command = NSScriptCommand.current()
        command?.scriptErrorNumber = -10006  // errAEWriteDenied
        command?.scriptErrorString = "A window's mode is set when it's made: make new window with properties {incognito:true}."
    }

    @objc var activeTab: AppleScriptTabWrapper? { controller?.selectedTabID.map { AppleScriptTabWrapper(tab: $0, window: self) } }
    @objc var activeSpace: AppleScriptSpaceWrapper? { controller.map { AppleScriptSpaceWrapper(space: $0.focusedSpaceID, window: self) } }

    /// Every space's tabs, as Arc lists them (#428): the open space first, in its ⌘1…⌘9 order,
    /// then the others; a shared favorite once (AppleScriptTabOrder).
    @objc var appleScriptTabs: [AppleScriptTabWrapper] {
        guard let controller else { return [] }
        return AppleScriptTabOrder.window(focused: controller.focusedSpaceID, spaces: appleScriptSpaces.map(\.spaceID), tabs: tabIDs(in:))
            .map { AppleScriptTabWrapper(tab: $0, window: self) }
    }

    @objc var appleScriptSpaces: [AppleScriptSpaceWrapper] {
        guard let controller else { return [] }
        guard !controller.isStandalone else { return [AppleScriptSpaceWrapper(space: controller.focusedSpaceID, window: self)] }
        let store = controller.store
        return store.orderedSpaces.filter { !store.isStandalone(space: $0.id) }.map { AppleScriptSpaceWrapper(space: $0.id, window: self) }
    }

    func tabIDs(in spaceID: UUID) -> [UUID] {
        guard let store = controller?.store, let space = store.space(spaceID) else { return [] }
        return (store.tabs(under: space.favoritesContainerID) + store.tabs(under: space.pinnedContainerID)
            + store.tabs(under: space.todayContainerID)).map(\.id)
    }

    /// make new tab at end of tabs of window 1 with properties {URL:"…"}: a Today tab, opened.
    @objc func insertInAppleScriptTabs(_ tab: AppleScriptTabWrapper) {
        guard let controller else { return }
        let url = tab.pendingURL ?? ""
        if url.isEmpty { controller.openCommandBar(.newTab); return }
        let item = controller.store.createTab(url: url, in: controller.focusedSpaceID, select: true, window: controller.windowID)
        tab.attach(item.id, window: self)
    }

    @objc func close(_ command: NSScriptCommand) -> Any? {
        controller?.window?.performClose(nil)
        return nil
    }

    /// `window id "…"`, so a command can return a window (make new window, get window 1). Asked of
    /// NSApplication by name: NSApp is Chrome's BrowserCrApplication, whose classDescription is nil.
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard controller != nil, let appDescription = NSScriptClassDescription(for: NSApplication.self) else { return nil }
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
        guard let controller = window.controller else { return "" }
        return controller.isBlank ? "This Window" : controller.store.space(spaceID)?.title ?? ""
    }
    /// Not in Arc (#438): the profile's name, so `pause media` and scripts can pick a profile.
    @objc var profile: String {
        guard let store = window.controller?.store else { return "" }
        return store.profile(store.space(spaceID)?.profileID)?.name ?? CraPauseMediaCommand.defaultProfile
    }
    @objc var appleScriptTabs: [AppleScriptTabWrapper] {
        window.tabIDs(in: spaceID).map { AppleScriptTabWrapper(tab: $0, window: window) }
    }

    @objc func focus(_ command: NSScriptCommand) -> Any? {
        if let controller = window.controller { controller.store.focusSpace(spaceID, window: controller.windowID) }
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
            // Not over an incognito tab: a tab in the normal window, as createTab sends it (#412).
            if controller.store.isIncognito(item: tabID), !IncognitoPages.allows(newValue) {
                controller.store.createTab(url: newValue, in: controller.store.spaceID(ofItem: tabID))
                return
            }
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

/// `pause media [only …] [except …] [profile "…"] [closing picture in picture …]` (GitHub #438, not
/// in Arc): Pause All Media for scripts. Answers {paused:n, kept playing:{titles}} once every page
/// has been checked, about a second later.
@objc(CraPauseMediaCommand)
final class CraPauseMediaCommand: NSScriptCommand {
    static let defaultProfile = "Default"

    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { run() }
        return nil
    }

    @MainActor private func run() {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let args = evaluatedArguments ?? [:]
        var scope = MediaPause.Scope(except: Self.names(args["except"]))
        if args["only"] != nil { scope.only = Self.names(args["only"]) }
        if let name = args["profile"] as? String {
            if name == Self.defaultProfile {
                scope.profile = .some(nil)
            } else if let p = app.store.profiles.first(where: { $0.name == name }) {
                scope.profile = .some(p.id)
            } else {
                scriptErrorNumber = -1728  // errAENoSuchObject
                scriptErrorString = "Cra has no profile named \"\(name)\"."
                return
            }
        }
        let close = args["closePictureInPicture"] as? Bool ?? false
        let targets = app.mediaPauseTargets().filter { MediaPause.isTarget($0.page, in: scope) }
        suspendExecution()
        PauseAllMedia.run(targets, closingPictureInPicture: close) { [self] report in
            CraLog.note("pause media (AppleScript): \(targets.count) pages, paused \(report.paused.count), kept playing \(report.keptPlaying.count)")
            resumeExecution(withResult: ["paused": report.paused.count, "keptPlaying": report.keptPlaying.map { targets[$0].title }] as NSDictionary)
        }
    }

    /// The windows, spaces and tabs a parameter names (one, or a list).
    @MainActor private static func names(_ value: Any?) -> MediaPause.Scope.Names {
        var names = MediaPause.Scope.Names()
        func add(_ v: Any?) {
            switch v {
            case let s as NSScriptObjectSpecifier: add(s.objectsByEvaluatingSpecifier)
            case let list as [Any]: list.forEach(add)
            case let w as AppleScriptWindowWrapper: if let id = w.controller?.windowID { names.windows.insert(id) }
            case let s as AppleScriptSpaceWrapper: names.spaces.insert(s.spaceID)
            case let t as AppleScriptTabWrapper: if let id = t.tabID { names.tabs.insert(id) }
            default: break
            }
        }
        add(value)
        return names
    }
}
